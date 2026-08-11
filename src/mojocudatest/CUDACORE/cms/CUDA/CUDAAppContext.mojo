from CUDACompat import CUDARuntime
from StreamCache import StreamCache
from EventCache import EventCache
from allocate_device import _AllocateDeviceState
from allocate_host import _AllocateHostState
from getCachingDeviceAllocator import _CachingAllocatorState


# Owns all formerly-global CUDA state for one application context.
# Must be heap-allocated (via UnsafePointer.alloc) so that stored raw
# pointers into its fields remain valid across moves of the owning struct.
# Movable only to allow the single init_pointee_move at heap-construction
# time; must NOT be moved after ScopedContext objects hold pointers into it.
struct CUDAAppContext(Movable):
    var runtime: CUDARuntime
    var stream_cache: StreamCache
    var event_cache: EventCache
    var device_state: _AllocateDeviceState
    var host_state: _AllocateHostState
    var caching_allocator_state: _CachingAllocatorState

    fn __init__(out self):
        self.runtime = CUDARuntime()
        self.stream_cache = StreamCache()
        self.event_cache = EventCache()
        self.device_state = _AllocateDeviceState()
        self.host_state = _AllocateHostState()
        self.caching_allocator_state = _CachingAllocatorState()

    fn __moveinit__(out self, deinit take: Self):
        self.runtime = take.runtime^
        self.stream_cache = take.stream_cache^
        self.event_cache = take.event_cache^
        self.device_state = take.device_state^
        self.host_state = take.host_state^
        self.caching_allocator_state = take.caching_allocator_state^
