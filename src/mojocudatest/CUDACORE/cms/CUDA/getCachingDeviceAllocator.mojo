from CachingDeviceAllocator import CachingDeviceAllocator
from std.gpu.host import DeviceContext
from deviceCount import deviceCount
from utils.lock import BlockingSpinLock, BlockingScopedLock


# C++: enum class Policy { Synchronous = 0, Asynchronous = 1, Caching = 2 };
struct Policy:
    alias Synchronous: Int = 0
    alias Asynchronous: Int = 1
    alias Caching: Int = 2


# C++ preprocessor knobs:
# #ifndef CUDATEST_DISABLE_CACHING_ALLOCATOR
# #elif CUDA_VERSION >= 11020 && !defined CUDATEST_DISABLE_ASYNC_ALLOCATOR
comptime CUDATEST_DISABLE_CACHING_ALLOCATOR: Bool = False
comptime CUDATEST_DISABLE_ASYNC_ALLOCATOR: Bool = False
comptime CUDA_VERSION: Int = 12000


fn _selectPolicy() -> Int:
    if not CUDATEST_DISABLE_CACHING_ALLOCATOR:
        return Policy.Caching
    if CUDA_VERSION >= 11020 and not CUDATEST_DISABLE_ASYNC_ALLOCATOR:
        return Policy.Asynchronous
    return Policy.Synchronous


# Growth factor (bin_growth in cub::CachingDeviceAllocator)
comptime binGrowth: UInt = 2
# Smallest bin, corresponds to binGrowth^minBin bytes
comptime minBin: UInt = 8
# Largest bin, corresponds to binGrowth^maxBin bytes
comptime maxBin: UInt = 30
# Total storage cap. 0 means "compute from available memory" in C++.
comptime maxCachedBytes: UInt = 0
# Fraction of total free memory used in C++ minCachedBytes()
comptime maxCachedFraction: Float64 = 0.8
comptime debug: Bool = False


struct _CachingAllocatorState(Movable):
    var policy: Int
    var _allocator_lock: BlockingSpinLock
    var _allocator_initialized: Bool
    var _allocator_ptr: UnsafePointer[CachingDeviceAllocator, MutAnyOrigin]

    fn __init__(out self):
        self.policy = _selectPolicy()
        self._allocator_lock = BlockingSpinLock()
        self._allocator_initialized = False
        self._allocator_ptr = UnsafePointer[CachingDeviceAllocator, MutAnyOrigin]()

    fn __moveinit__(out self, var take: Self):
        self.policy = take.policy
        self._allocator_lock = BlockingSpinLock()
        self._allocator_initialized = take._allocator_initialized
        self._allocator_ptr = take._allocator_ptr

    fn __del__(var self):
        if self._allocator_initialized and self._allocator_ptr != UnsafePointer[CachingDeviceAllocator, MutAnyOrigin]():
            self._allocator_ptr.destroy_pointee()
            self._allocator_ptr.free()

    fn getCachingDeviceAllocator(mut self) -> UnsafePointer[CachingDeviceAllocator, MutAnyOrigin]:
        with BlockingScopedLock(self._allocator_lock):
            if not self._allocator_initialized:
                if debug:
                    _printSettings()
                self._allocator_ptr = alloc[CachingDeviceAllocator](1)
                __get_address_as_uninit_lvalue(self._allocator_ptr.address) = CachingDeviceAllocator(
                    binGrowth,
                    minBin,
                    maxBin,
                    minCachedBytes(),
                    False,  # do not skip cleanup
                    debug
                )
                self._allocator_initialized = True
            return self._allocator_ptr


fn minCachedBytes() -> UInt:
    var ret: UInt = UInt.MAX
    var number_of_devices = deviceCount()

    for i in range(number_of_devices):
        try:
            var ctx = DeviceContext(api="cuda", device_id = i)
            var (free_mem, total_mem) = ctx.get_memory_info()
            _ = total_mem

            var free_bytes = UInt(free_mem)
            var candidate = UInt(Float64(free_bytes) * maxCachedFraction)
            if candidate < ret:
                ret = candidate
        except e:
            pass

    if maxCachedBytes > 0:
        if maxCachedBytes < ret:
            ret = maxCachedBytes
    return ret


fn _formatBinSize(bin_size: UInt) -> String:
    var gib = UInt(1 << 30)
    var mib = UInt(1 << 20)
    var kib = UInt(1 << 10)
    if bin_size >= gib and (bin_size % gib) == 0:
        return String(bin_size >> 30) + " GB"
    if bin_size >= mib and (bin_size % mib) == 0:
        return String(bin_size >> 20) + " MB"
    if bin_size >= kib and (bin_size % kib) == 0:
        return String(bin_size >> 10) + " kB"
    return String(bin_size) + " B"


fn _printSettings():
    print("cub::CachingDeviceAllocator settings")
    print("  bin growth " + String(binGrowth))
    print("  min bin    " + String(minBin))
    print("  max bin    " + String(maxBin))
    print("  resulting bins:")
    var bin = minBin
    while bin <= maxBin:
        var bin_size = CachingDeviceAllocator.IntPow(binGrowth, bin)
        print("    " + _formatBinSize(bin_size))
        bin += 1
    print(
        "  maximum amount of cached memory: "
        + String(minCachedBytes() >> 20)
        + " MB"
    )
