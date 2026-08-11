# Mojo port of CUDACore/allocate_device.h
from std.gpu.host import DeviceContext
from std.gpu.host.device_context import DeviceBuffer
from builtin.dtype import DType
from utils.lock import BlockingSpinLock, BlockingScopedLock
from CUDACompat import CUDAStreamType


# Standardized stream handle used across this Mojo CUDA layer.
alias cudaStream_t = CUDAStreamType

# Device pointer equivalent to void* in C++.
alias DevicePtr = UnsafePointer[UInt8, MutAnyOrigin]
alias ByteDeviceBuffer = DeviceBuffer[DType.uint8]


struct _AllocateDeviceState(Movable):
    var _lock: BlockingSpinLock
    var _allocated_buffers: List[Tuple[UInt, ByteDeviceBuffer]]

    fn __init__(out self):
        self._lock = BlockingSpinLock()
        self._allocated_buffers = List[Tuple[UInt, ByteDeviceBuffer]]()

    fn __moveinit__(out self, deinit take: Self):
        self._lock = BlockingSpinLock()
        self._allocated_buffers = take._allocated_buffers^

    # Allocate device memory.
    fn allocate_device(mut self, device: Int32, nbytes: UInt, stream: cudaStream_t) -> DevicePtr:
        _ = stream
        if nbytes == 0:
            return DevicePtr()
        try:
            # keep the DeviceBuffer alive as long as you intend to use the pointer.
            var ctx = DeviceContext(api="cuda", device_id = Int(device))
            var buffer = ctx.create_buffer_sync[DType.uint8](Int(nbytes))
            var ptr = buffer.unsafe_ptr()
            if ptr != DevicePtr():
                with BlockingScopedLock(self._lock):
                    self._allocated_buffers.append((UInt(Int(ptr)), buffer))
            return ptr
        except e:
            return DevicePtr()

    # Free device memory (to be called from unique_ptr).
    fn free_device(mut self, device: Int32, ptr: DevicePtr, stream: cudaStream_t):
        _ = device
        _ = stream
        if ptr == DevicePtr():
            return
        #TODO replace this with a set to make faster
        with BlockingScopedLock(self._lock):
            var target = UInt(Int(ptr))
            var i = 0
            while i < self._allocated_buffers.__len__():
                if self._allocated_buffers[i][0] == target:
                    try:
                        _ = self._allocated_buffers.pop(i)
                    except:
                        pass
                    break
                i += 1
