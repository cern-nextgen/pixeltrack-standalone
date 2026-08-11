from std.gpu.host import DeviceContext

from CUDACompat import CUDAStreamType, cudaGetDevice
from SharedStreamPtr import SharedStreamPtr
from deviceCount import deviceCount

from Framework.ReusableObjectHolder import (
    ReusableObjectHolder,
    ReusableObjectMaker,
    makeOrGet,
)


struct StreamMaker(ReusableObjectMaker, Movable):
    alias Output = CUDAStreamType

    var dev: Int

    fn __init__(out self, dev: Int):
        self.dev = dev

    def make(mut self) -> CUDAStreamType:
        try:
            var ctx = DeviceContext(api="cuda", device_id=self.dev)
            return CUDAStreamType(ctx.create_stream())
        except:
            return CUDAStreamType()


# Gets a (cached) CUDA stream for the current device. The stream is returned
# to the cache when the SharedStreamPtr reference count drops to zero.
# This function is thread safe.
struct StreamCache(Movable):
    var cache_: List[UnsafePointer[ReusableObjectHolder[CUDAStreamType], MutAnyOrigin]]

    fn __init__(out self):
        self.cache_ = List[UnsafePointer[ReusableObjectHolder[CUDAStreamType], MutAnyOrigin]]()
        for _ in range(deviceCount()):
            var slot = alloc[ReusableObjectHolder[CUDAStreamType]](1)
            __get_address_as_uninit_lvalue(slot.address) = ReusableObjectHolder[CUDAStreamType]()
            self.cache_.append(slot)

    fn __moveinit__(out self, deinit take: Self):
        self.cache_ = take.cache_^

    fn __del__(var self):
        for i in range(self.cache_.__len__()):
            self.cache_[i].destroy_pointee()
            self.cache_[i].free()

    fn get(mut self) raises -> SharedStreamPtr:
        var dev: Int = 0
        _ = cudaGetDevice(dev)
        var maker = StreamMaker(dev)
        return makeOrGet[StreamMaker](self.cache_[dev][], maker)

    # Not thread safe — intended to be called only from CUDAService destructor.
    fn clear(mut self):
        for i in range(self.cache_.__len__()):
            self.cache_[i][].clear()
