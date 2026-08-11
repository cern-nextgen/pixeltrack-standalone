from getCachingDeviceAllocator import _CachingAllocatorState
from CachingDeviceAllocator import GpuCachedBytes


# C++ shape: cms::cuda::deviceAllocatorStatus()
@always_inline
fn deviceAllocatorStatus(mut state: _CachingAllocatorState) -> GpuCachedBytes:
    return state.getCachingDeviceAllocator()[].CacheStatus()


