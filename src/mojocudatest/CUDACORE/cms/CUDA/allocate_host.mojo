from std.gpu.host import DeviceContext
from std.gpu.host.device_context import HostBuffer
from builtin.dtype import DType
from builtin.error import Error
from builtin.int import Int
from CUDACompat import CUDAStreamType, cudaStreamDefault
from CachingDeviceAllocator import CachingDeviceAllocator
from getCachingDeviceAllocator import binGrowth, maxBin
from utils.lock import BlockingSpinLock, BlockingScopedLock


alias HostPtr = UnsafePointer[UInt8, MutAnyOrigin]
alias ByteHostBuffer = HostBuffer[DType.uint8]
alias cudaStream_t = CUDAStreamType


struct _AllocateHostState(Movable):
    var _lock: BlockingSpinLock
    var _allocated_host_buffers: List[Tuple[UInt, ByteHostBuffer]]

    fn __init__(out self):
        self._lock = BlockingSpinLock()
        self._allocated_host_buffers = List[Tuple[UInt, ByteHostBuffer]]()

    fn __moveinit__(out self, deinit take: Self):
        self._lock = BlockingSpinLock()
        self._allocated_host_buffers = take._allocated_host_buffers^

    # Raw pinned-host allocation primitive. CachingHostAllocator must use this
    # to avoid recursing through the public allocate_host()/free_host() wrapper.
    fn allocate_host_raw(
        mut self,
        nbytes: UInt,
        stream: cudaStream_t = cudaStreamDefault,
        device: Int32 = Int32(-1)
    ) -> HostPtr:
        _ = stream
        if nbytes == 0:
            return HostPtr()

        try:
            var ctx = DeviceContext(api="cuda")
            if device >= Int32(0):
                ctx = DeviceContext(api="cuda", device_id = Int(device))
            var buf = ctx.enqueue_create_host_buffer[DType.uint8](Int(nbytes))
            ctx.synchronize()          # ensure allocation is complete

            var ptr = buf.unsafe_ptr()
            if ptr != HostPtr():
                with BlockingScopedLock(self._lock):
                    self._allocated_host_buffers.append((UInt(ptr.address), buf))
            return ptr
        except e:
            return HostPtr()

    fn free_host_raw(mut self, ptr: HostPtr):
        if ptr == HostPtr():
            return

        with BlockingScopedLock(self._lock):
            var target = UInt(ptr.address)
            var i = 0
            while i < self._allocated_host_buffers.__len__():
                if self._allocated_host_buffers[i][0] == target:
                    try:
                        _ = self._allocated_host_buffers.pop(i)
                    except:
                        pass
                    break
                i += 1


fn _max_allocation_size() -> UInt:
    return CachingDeviceAllocator.IntPow(binGrowth, maxBin)
