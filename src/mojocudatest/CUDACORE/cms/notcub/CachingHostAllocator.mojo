#/******************************************************************************
# * Copyright (c) 2011, Duane Merrill.  All rights reserved.
# * Copyright (c) 2011-2018, NVIDIA CORPORATION.  All rights reserved.
# *
# * Redistribution and use in source and binary forms, with or without
# * modification, are permitted provided that the following conditions are met:
# *     * Redistributions of source code must retain the above copyright
# *       notice, this list of conditions and the following disclaimer.
# *     * Redistributions in binary form must reproduce the above copyright
# *       notice, this list of conditions and the following disclaimer in the
# *       documentation and/or other materials provided with the distribution.
# *     * Neither the name of the NVIDIA CORPORATION nor the
# *       names of its contributors may be used to endorse or promote products
# *       derived from this software without specific prior written permission.
# *
# * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
# * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *
# ******************************************************************************/
#
#/**
# * Modified to cache pinned host allocations by Matti Kortelainen
# */
#
#/******************************************************************************
# * Simple caching allocator for pinned host memory allocations. The allocator is
# * thread-safe.
# ******************************************************************************/

#Ported to Mojo by Abbas Naim

from CUDACompat import (
    CUDAStreamType,
    CUDAEventType,
    CUDARuntime,
    cudaStreamDefault,
    cudaGetDevice,
    cudaEventCreateWithFlags,
    cudaEventDestroy,
    cudaEventQuery,
    cudaEventRecord,
)
from allocate_host import _AllocateHostState
from MojoBridge.OrderedMultiSet import OrderedMultiSet
from MojoBridge.DTypes import (
    cudaError_t,
    cudaSuccess,
    cudaErrorNotReady,
    cudaErrorMemoryAllocation,
    cudaEventDisableTiming,
)
from utils.lock import BlockingSpinLock, BlockingScopedLock

@fieldwise_init
struct CachingHostAllocator(Movable, Sized):

    #---------------------------------------------------------------------
    # Constants
    #---------------------------------------------------------------------

    # Out-of-bounds bin
    comptime INVALID_BIN : UInt = UInt.MAX


    comptime INVALID_SIZE : UInt = UInt.MAX

    # the following is not to be documented
 
    comptime INVALID_DEVICE_ORDINAL : Int = -1


    #---------------------------------------------------------------------
    # Type definitions and helper types
    #---------------------------------------------------------------------

    alias cudaStream_t = CUDAStreamType
    alias cudaEvent_t = CUDAEventType
    alias DevicePtr = UnsafePointer[UInt8]

    """
      Descriptor for device memory allocations
    """
    struct BlockDescriptor:
        var d_ptr : DevicePtr
        var bytes : UInt
        var bin : UInt
        var device : Int
        var associated_stream : cudaStream_t
        var ready_event : cudaEvent_t

        # Constructor for lookup by (pointer, device).
        @always_inline
        fn __init__(
            out self,
            d_ptr: DevicePtr
        ):
            self.d_ptr = d_ptr
            self.bytes = 0

            self.bin = INVALID_BIN
            self.device = INVALID_DEVICE_ORDINAL
            self.associated_stream = cudaStream_t()
            self.ready_event = cudaEvent_t()

        # Constructor for lookup ranges by device.
        @always_inline
        fn __init__(out self):
            self.d_ptr = DevicePtr()
            self.bytes = 0

            self.bin = INVALID_BIN
            self.device = INVALID_DEVICE_ORDINAL
            self.associated_stream = cudaStream_t()
            self.ready_event = cudaEvent_t()


        @always_inline
        @staticmethod
        fn PtrCompare(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
            return a.d_ptr.address < b.d_ptr.address


        @always_inline
        @staticmethod
        fn SizeCompare(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
            return a.bytes < b.bytes


    struct BlockByPtrCompare:
        @always_inline
        @staticmethod
        fn less(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
            return BlockDescriptor.PtrCompare(a, b)

    struct BlockBySizeCompare:
        @always_inline
        @staticmethod
        fn less(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
            return BlockDescriptor.SizeCompare(a, b)


    @fieldwise_init
    struct TotalBytes(Copyable, Defaultable, Movable):
        var free: UInt
        var live: UInt

        @always_inline
        fn __init__(out self):
            self.free = 0
            self.live = 0

    alias CachedBlocks = OrderedMultiSet[BlockDescriptor, BlockBySizeCompare]
    alias BusyBlocks = OrderedMultiSet[BlockDescriptor, BlockByPtrCompare]

    #---------------------------------------------------------------------
    # Utility functions
    #---------------------------------------------------------------------

    @always_inline
    @staticmethod
    fn IntPow(base: UInt, exp: UInt) -> UInt:
        var b = base
        var e = exp
        var retval: UInt = 1
        while e > 0:
            if (e & 1) != 0:
                retval = retval * b
            b = b * b
            e = e >> 1
        return retval

    @always_inline
    @staticmethod
    fn NearestPowerOf(
        out power: UInt,
        out rounded_bytes: UInt,
        base: UInt,
        value: UInt
    ):
        power = 0
        rounded_bytes = 1

        if value * base < value:
            # Overflow
            power = UInt(8 * sizeof[UInt]())
            rounded_bytes = UInt.MAX
            return

        while rounded_bytes < value:
            rounded_bytes *= base
            power += 1

    #---------------------------------------------------------------------
    # Fields
    #---------------------------------------------------------------------

    # CMS: use std::mutex instead of cub::Mutex, declare mutable
    var mutex: BlockingSpinLock  # Mutex for thread-safety

    var bin_growth: UInt  # Geometric growth factor for bin-sizes
    var min_bin: UInt  # Minimum bin enumeration
    var max_bin: UInt  # Maximum bin enumeration

    var min_bin_bytes: UInt  # Minimum bin size
    var max_bin_bytes: UInt  # Maximum bin size
    var max_cached_bytes: UInt  # Maximum aggregate cached bytes

    var skip_cleanup: Bool  # Whether or not to skip a call to FreeAllCached() when destructor is called.  (The CUDA runtime may have already shut down for statically declared allocators)
    var debug: Bool  # Whether or not to print (de)allocation events to stdout

    var cached_bytes: TotalBytes  # Aggregate cached bytes
    var cached_blocks: CachedBlocks  # Set of cached device allocations available for reuse
    var live_blocks: BusyBlocks  # Set of live device allocations currently in use

    var host_runtime: CUDARuntime  # Isolated runtime for internal event bookkeeping
    var host_alloc_state: _AllocateHostState  # Isolated host allocation state for pool blocks

    #---------------------------------------------------------------------
    # Methods
    #---------------------------------------------------------------------

    #/**
    # * \brief Constructor.
    # */
    fn __init__(
        out self,
        bin_growth: UInt,
        min_bin: UInt = 1,
        max_bin: UInt = INVALID_BIN,
        max_cached_bytes: UInt = INVALID_SIZE,
        skip_cleanup: Bool = False,
        debug: Bool = False
    ):
        self.mutex = BlockingSpinLock()
        self.bin_growth = bin_growth
        self.min_bin = min_bin
        self.max_bin = max_bin
        self.min_bin_bytes = CachingHostAllocator.IntPow(bin_growth, min_bin)
        self.max_bin_bytes = CachingHostAllocator.IntPow(bin_growth, max_bin)
        self.max_cached_bytes = max_cached_bytes
        self.skip_cleanup = skip_cleanup
        self.debug = debug
        self.cached_bytes = TotalBytes()
        self.cached_blocks = CachedBlocks()
        self.live_blocks = BusyBlocks()
        self.host_runtime = CUDARuntime()
        self.host_alloc_state = _AllocateHostState()

    #/**
    # * \brief Default constructor.
    # *
    # * Configured with:
    # * \par
    # * - \p bin_growth          = 8
    # * - \p min_bin             = 3
    # * - \p max_bin             = 7
    # * - \p max_cached_bytes    = (\p bin_growth ^ \p max_bin) * 3) - 1 = 6,291,455 bytes
    # *
    # * which delineates five bin-sizes: 512B, 4KB, 32KB, 256KB, and 2MB and
    # * sets a maximum of 6,291,455 cached bytes per device
    # */
    fn __init__(out self, skip_cleanup: Bool = False, debug: Bool = False):
        self.mutex = BlockingSpinLock()
        self.bin_growth = 8
        self.min_bin = 3
        self.max_bin = 7
        self.min_bin_bytes = CachingHostAllocator.IntPow(
            self.bin_growth, self.min_bin
        )
        self.max_bin_bytes = CachingHostAllocator.IntPow(
            self.bin_growth, self.max_bin
        )
        self.max_cached_bytes = (self.max_bin_bytes * 3) - 1
        self.skip_cleanup = skip_cleanup
        self.debug = debug
        self.cached_bytes = TotalBytes()
        self.cached_blocks = CachedBlocks()
        self.live_blocks = BusyBlocks()
        self.host_runtime = CUDARuntime()
        self.host_alloc_state = _AllocateHostState()

    #/**
    # * \brief Sets the limit on the number bytes this allocator is allowed to cache per device.
    # *
    # * Changing the ceiling of cached bytes does not cause any allocations (in-use or
    # * cached-in-reserve) to be freed.  See \p FreeAllCached().
    # */
    fn SetMaxCachedBytes(mut self, max_cached_bytes: UInt) :
        with BlockingScopedLock(self.mutex):
            if self.debug:
                print(
                    "Changing max_cached_bytes ("
                    + String(self.max_cached_bytes)
                    + " -> "
                    + String(max_cached_bytes)
                    + ")"
                )
            self.max_cached_bytes = max_cached_bytes

    fn DeviceAllocate(
        mut self,
        out d_ptr: DevicePtr,
        bytes: UInt,
        active_stream: cudaStream_t = cudaStreamDefault
    ) -> cudaError_t raises:
        # CMS: use RAII instead of (un)locking explicitly
        d_ptr = DevicePtr()
        var device = INVALID_DEVICE_ORDINAL
        var error: cudaError_t = cudaSuccess



        error = cudaGetDevice(device)


        # Create a block descriptor for the requested allocation
        var found = False
        var search_key = BlockDescriptor()
        search_key.device = device
        search_key.associated_stream = active_stream
        CachingHostAllocator.NearestPowerOf(
            search_key.bin, search_key.bytes, self.bin_growth, bytes
        )

        if search_key.bin > self.max_bin:
            # Bin is greater than our maximum bin: allocate the request
            # exactly and give out-of-bounds bin.  It will not be cached
            # for reuse when returned.
            search_key.bin = INVALID_BIN
            search_key.bytes = bytes
        else:
            # Search for a suitable cached allocation: lock
            with BlockingScopedLock(self.mutex):
                if search_key.bin < self.min_bin:
                    # Bin is less than minimum bin: round up
                    search_key.bin = self.min_bin
                    search_key.bytes = self.min_bin_bytes

                # Iterate through the range of cached blocks on the same device in the same bin
                var block_itr = self.cached_blocks.lower_bound(search_key)
                while (
                    (block_itr != self.cached_blocks.__len__()) and
                    (self.cached_blocks[block_itr].bin == search_key.bin)
                ):
                    # To prevent races with reusing blocks returned by the host but still
                    # in use for transfers, only consider cached blocks that are
                    # either from an idle stream
                    if (
                        (cudaEventQuery(self.cached_blocks[block_itr].ready_event) != cudaErrorNotReady)
                    ):
                        # Reuse existing cache block.  Insert into live blocks.
                        found = True
                        search_key = self.cached_blocks[block_itr]
                        search_key.associated_stream = active_stream
                        if search_key.device != device:
                            # C++ changes current device around event recreation.
                            # In this Mojo port, event handles are runtime-managed, so we only
                            # need to recreate the event and update the associated device tag.
                            error = cudaEventDestroy(search_key.ready_event)
                            if error != cudaSuccess:
                                return error
                            error = cudaEventCreateWithFlags(
                                search_key.ready_event,
                                cudaEventDisableTiming,
                                self.host_runtime
                            )
                            if error != cudaSuccess:
                                return error
                            search_key.device = device
                        self.live_blocks.insert(search_key)

                        # Remove from free blocks
                        self.cached_bytes.free -= search_key.bytes
                        self.cached_bytes.live += search_key.bytes

                        if self.debug:
                            print(
                                "\Host "
                                + " reused cached block at "
                                + String(search_key.d_ptr.address)
                                + " ("
                                + String(search_key.bytes)
                                + " bytes) for stream "
                                + String(search_key.associated_stream)
                                + ", event "
                                + String(search_key.ready_event.event_id)
                                + "on device "
                                + String(search_key.device)
                                + " (previously associated with stream "
                                + String(self.cached_blocks[block_itr].associated_stream)
                                + ", event "
                                + String(self.cached_blocks[block_itr].ready_event.event_id)
                                + ")."
                            )

                        _ = self.cached_blocks.erase_at(block_itr)

                        break
                    block_itr += 1

            # Done searching: unlock

        # Allocate the block if necessary
        if not found:


            # Attempt to allocate
            # TODO: eventually support allocation flags
            try:
                let ptr = self.host_alloc_state.allocate_host_raw(search_key.bytes)
                if ptr == DevicePtr():
                    error = cudaErrorMemoryAllocation
                else:
                    search_key.d_ptr = ptr
                    error = cudaSuccess
            except e:
                error = cudaErrorMemoryAllocation

            if error == cudaErrorMemoryAllocation:
                # The allocation attempt failed: free all cached blocks on device and retry
                if self.debug:
                    print(
                        "\Host "
                        + " failed to allocate "
                        + String(search_key.bytes)
                        + " bytes for stream "
                        + String(search_key.associated_stream)
                        + ", retrying after freeing cached allocations"
                        + String(search_key.device)
                    )

                error = cudaSuccess
                #TODO implement get last error in mojo 

                # Iterate the range of free blocks on the same device
                with BlockingScopedLock(self.mutex):
                    var block_itr = self.cached_blocks.lower_bound()

                    while (
                        (block_itr != self.cached_blocks.__len__())
                    ):
                        var block = self.cached_blocks[block_itr]

                        # No need to worry about synchronization with the device: cudaFree is
                        # blocking and will synchronize across all kernels executing
                        # on the current device


                        # Free pinned memory.
                        
                        # the mojo implemetation of cudaFree and it doesnt
                        # return an error 
                        self.host_alloc_state.free_host_raw(block.d_ptr)
                        error = cudaEventDestroy(block.ready_event)
                        if error != cudaSuccess:
                            break

                        # Reduce balance and erase entry
                        self.cached_bytes.free -= block.bytes

                        if self.debug:
                            print(
                                "\Host "
                                + " freed "
                                + String(block.bytes)
                                + " bytes.\n\t\t  "
                                + String(self.cached_blocks.__len__())
                                + " available blocks cached ("
                                + String(self.cached_bytes.free)
                                + " bytes), "
                                + String(self.live_blocks.__len__())
                                + " live blocks ("
                                + String(self.cached_bytes.live)
                                + " bytes) outstanding."
                            )

                        _ = self.cached_blocks.erase_at(block_itr)

                        block_itr += 1

                if error != cudaSuccess:
                    return error

                # Try to allocate again
                try:
                    let ptr = self.host_alloc_state.allocate_host_raw(search_key.bytes)
                    if ptr == DevicePtr():
                        error = cudaErrorMemoryAllocation
                    else:
                        search_key.d_ptr = ptr
                        error = cudaSuccess
                except e:
                    error = cudaErrorMemoryAllocation
                    return cudaErrorMemoryAllocation
                if error == cudaErrorMemoryAllocation:
                    return cudaErrorMemoryAllocation


            # Create ready event
            # NOTE this is temporary and its not actually doing
            # Anything with the flags
            error = cudaEventCreateWithFlags(
                search_key.ready_event,
                cudaEventDisableTiming,
                self.host_runtime
            )
            if error != cudaSuccess:
                return error

            # Insert into live blocks
            with BlockingScopedLock(self.mutex):
                self.live_blocks.insert(search_key)
                self.cached_bytes.live += search_key.bytes

            if self.debug:
                print(
                    "\tHost "
                    + " allocated new device block at "
                    + String(search_key.d_ptr.address)
                    + " ("
                    + String(search_key.bytes)
                    + " bytes associated with stream "
                    + String(search_key.associated_stream)
                    + ", event "
                    + String(search_key.ready_event.event_id)
                    + "on device"+
                    String(search_key.device)
                    ")."
                )

        # Copy host pointer to output parameter
        d_ptr = search_key.d_ptr

        if self.debug:
            print(
                "\t\t"
                + String(self.cached_blocks.__len__())
                + " available blocks cached ("
                + String(self.cached_bytes.free)
                + " bytes), "
                + String(self.live_blocks.__len__())
                + " live blocks outstanding("
                + String(self.cached_bytes.live)
                + " bytes)."
            )

        return error


fn HostFree(
    mut self,
    d_ptr: DevicePtr
) -> cudaError_t raises:
    var error: cudaError_t = cudaSuccess
    var recached = False
    var search_key = BlockDescriptor(d_ptr)


    # search_key.device = device
    with BlockingScopedLock(self.mutex):
        var block_itr = self.live_blocks.find(search_key)
        if block_itr != -1:
            search_key = self.live_blocks[block_itr]
            _ = self.live_blocks.erase_at(block_itr)
            self.cached_bytes.live -= search_key.bytes

            # Keep the returned allocation if bin is valid and we won't exceed the max cached threshold.
            if (
                (search_key.bin != INVALID_BIN) and
                (self.cached_bytes.free + search_key.bytes <= self.max_cached_bytes)
            ):
                recached = True
                self.cached_blocks.insert(search_key)
                self.cached_bytes.free += search_key.bytes
                if self.debug:
                    print(
                        "\tHost "
                        + " returned "
                        + String(search_key.bytes)
                        + " bytes at "
                        + " from associated stream "
                        + String(search_key.associated_stream)
                        + ", event "
                        + String(search_key.ready_event.event_id)
                        + " on device "
                        + String(search_key.device)
                        + ".\n\t\t "
                        + String(self.cached_blocks.__len__())
                        + " available blocks cached ("
                        + String(self.cached_bytes.free)
                        + " bytes), "
                        + String(self.live_blocks.__len__())
                        + " live blocks outstanding. ("
                        + String(self.cached_bytes.live)
                        + " bytes)"
                    )
        if recached:
            # Insert the ready event in the associated stream.
            error = cudaEventRecord(search_key.ready_event, search_key.associated_stream)
            if error != cudaSuccess:
                return error
    if not recached:
        # Free the allocation from the runtime and cleanup the event.
        self.host_alloc_state.free_host_raw(d_ptr)
        error = cudaEventDestroy(search_key.ready_event)
        if error != cudaSuccess:
            return error
        if self.debug:
            print(
                "\tHost "
                + " freed "
                + String(search_key.bytes)
                + " bytes "
                + " from associated stream "
                + String(search_key.associated_stream)
                + ", event "
                + String(search_key.ready_event.event_id)
                + " on device "
                + String(search_key.device)
                + ".\n\t\t  "
                + String(self.cached_blocks.__len__())
                + " available blocks cached ("
                + String(self.cached_bytes.free)
                + " bytes), "
                + String(self.live_blocks.__len__())
                + " live blocks ("
                + String(self.cached_bytes.live)
                + " bytes) outstanding."
            )
    return error


#/**
# * \brief Frees all cached device allocations on all devices.
# */
fn FreeAllCached(mut self) -> cudaError_t raises:
    var error: cudaError_t = cudaSuccess

    with BlockingScopedLock(self.mutex):
        while self.cached_blocks.__len__() > 0:
            var begin = self.cached_blocks[0]

            self.host_alloc_state.free_host_raw(begin.d_ptr)
            error = cudaEventDestroy(begin.ready_event)
            if error != cudaSuccess:
                return error

            self.cached_bytes.free -= begin.bytes

            if self.debug:
                print(
                    "\tDevice "
                    + String(begin.device)
                    + " freed "
                    + String(begin.bytes)
                    + " bytes.\n\t\t  "
                    + String(self.cached_blocks.__len__())
                    + " available blocks cached ("
                    + String(self.cached_bytes.free)
                    + " bytes), "
                    + String(self.live_blocks.__len__())
                    + " live blocks ("
                    + String(self.cached_bytes.live)
                    + " bytes) outstanding."
                )

            _ = self.cached_blocks.erase_at(0)

    return error
