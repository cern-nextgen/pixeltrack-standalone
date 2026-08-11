from CUDACompat import CUDAEventType, CUDARuntime, cudaEventCreateWithFlags
from MojoBridge.DTypes import cudaEventDisableTiming
from SharedEventPtr import SharedEventPtr, _EventCacheSlot, _EventOwner
from currentDevice import currentDevice
from cudaCheck import cudaCheck_
from deviceCount import deviceCount
from eventWorkHasCompleted import event_work_has_completed


struct EventCache(Movable):
    var cache_: List[UnsafePointer[_EventCacheSlot, MutAnyOrigin]]

    fn __init__(out self):
        self.cache_ = List[UnsafePointer[_EventCacheSlot, MutAnyOrigin]]()
        self._buildSlots()

    fn __moveinit__(out self, deinit take: Self):
        self.cache_ = take.cache_^

    fn __del__(var self):
        self._destroySlots()

    fn get(mut self, mut runtime: CUDARuntime) raises -> SharedEventPtr:
        var dev = currentDevice()
        var event = self.makeOrGet(dev, runtime)
        if event_work_has_completed(event[].event):
            return event^

        var incomplete = List[SharedEventPtr]()
        incomplete.append(event^)
        while True:
            event = self.makeOrGet(dev, runtime)
            if event_work_has_completed(event[].event):
                return event^
            incomplete.append(event^)

    fn makeOrGet(mut self, dev: Int, mut runtime: CUDARuntime) raises -> SharedEventPtr:
        var slot = self.cache_[dev]
        var cached = slot[].tryToGet()
        if cached:
            var event = cached.value()
            return SharedEventPtr(_EventOwner(event^, slot))

        var event = CUDAEventType()
        _ = cudaCheck_(
            "EventCache.mojo", 0,
            "cudaEventCreateWithFlags",
            cudaEventCreateWithFlags(event, cudaEventDisableTiming, runtime),
        )
        slot[].addNewOutstanding()
        var owner = SharedEventPtr(_EventOwner(event^, slot))
        return owner^

    fn clear(mut self):
        self._destroySlots()
        self._buildSlots()

    fn _buildSlots(mut self):
        for dev in range(deviceCount()):
            var slot = alloc[_EventCacheSlot](1)
            __get_address_as_uninit_lvalue(slot.address) = _EventCacheSlot(dev)
            self.cache_.append(slot)

    fn _destroySlots(mut self):
        for i in range(self.cache_.__len__()):
            var slot = self.cache_[i]
            slot[].clear()
            slot.destroy_pointee()
            slot.free()
        self.cache_.clear()
