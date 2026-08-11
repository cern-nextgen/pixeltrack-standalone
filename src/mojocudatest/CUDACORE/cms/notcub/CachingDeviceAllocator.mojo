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
# * Forked to CMSSW by Matti Kortelainen
# */
#
#/******************************************************************************
# * Simple caching allocator for device memory allocations. The allocator is
# * thread-safe and capable of managing device allocations on multiple devices.
# ******************************************************************************/

#
#
# Ported to Mojo by Abbas Naim
#
#





#/**
# * \addtogroup UtilMgmt
# * @{
# */
#
#  /******************************************************************************
# * CachingDeviceAllocator (host use)
# ******************************************************************************/
#
#  /**
# * \brief A simple caching allocator for device memory allocations.
# *
# * \par Overview
# * The allocator is thread-safe and stream-safe and is capable of managing cached
# * device allocations on multiple devices.  It behaves as follows:
# *
# * \par
# * - Allocations from the allocator are associated with an \p active_stream.  Once freed,
# *   the allocation becomes available immediately for reuse within the \p active_stream
# *   with which it was associated with during allocation, and it becomes available for
# *   reuse within other streams when all prior work submitted to \p active_stream has completed.
# * - Allocations are categorized and cached by bin size.  A new allocation request of
# *   a given size will only consider cached allocations within the corresponding bin.
# * - Bin limits progress geometrically in accordance with the growth factor
# *   \p bin_growth provided during construction.  Unused device allocations within
# *   a larger bin cache are not reused for allocation requests that categorize to
# *   smaller bin sizes.
# * - Allocation requests below (\p bin_growth ^ \p min_bin) are rounded up to
# *   (\p bin_growth ^ \p min_bin).
# * - Allocations above (\p bin_growth ^ \p max_bin) are not rounded up to the nearest
# *   bin and are simply freed when they are deallocated instead of being returned
# *   to a bin-cache.
# * - %If the total storage of cached allocations on a given device will exceed
# *   \p max_cached_bytes, allocations for that device are simply freed when they are
# *   deallocated instead of being returned to their bin-cache.
# *
# * \par
# * For example, the default-constructed CachingDeviceAllocator is configured with:
# * - \p bin_growth          = 8
# * - \p min_bin             = 3
# * - \p max_bin             = 7
# * - \p max_cached_bytes    = 6MB - 1B
# *
# * \par
# * which delineates five bin-sizes: 512B, 4KB, 32KB, 256KB, and 2MB
# * and sets a maximum of 6,291,455 cached bytes per device
# *
# */

from deviceAllocatorStatus import GpuCachedBytes, TotalBytes
from std.sys.info import size_of
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
from allocate_device import _AllocateDeviceState
from MojoBridge.OrderedMultiSet import OrderedMultiSet
from MojoBridge.DTypes import (
    cudaError_t,
    cudaSuccess,
    cudaErrorNotReady,
    cudaErrorMemoryAllocation,
    cudaEventDisableTiming,
)
from utils.lock import BlockingSpinLock, BlockingScopedLock

# Descriptor for device memory allocations
struct BlockDescriptor(Copyable, Movable, ImplicitlyCopyable):
    var d_ptr : UnsafePointer[UInt8, MutAnyOrigin]
    var bytes : UInt
    var bytesRequested : UInt
    var bin : UInt
    var device : Int
    var associated_stream : CUDAStreamType
    var ready_event : CUDAEventType

    # Constructor for lookup by (pointer, device).
    @always_inline
    fn __init__(
        out self,
        d_ptr: UnsafePointer[UInt8, MutAnyOrigin],
        device: Int
    ):
        self.d_ptr = d_ptr
        self.bytes = 0
        self.bytesRequested = 0
        self.bin = UInt.MAX
        self.device = device
        self.associated_stream = CUDAStreamType()
        self.ready_event = CUDAEventType()

    # Constructor for lookup ranges by device.
    @always_inline
    fn __init__(out self, device: Int):
        self.d_ptr = UnsafePointer[UInt8, MutAnyOrigin]()
        self.bytes = 0
        self.bytesRequested = 0
        self.bin = UInt.MAX
        self.device = device
        self.associated_stream = CUDAStreamType()
        self.ready_event = CUDAEventType()


    @always_inline
    @staticmethod
    fn PtrCompare(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
        if a.device == b.device:
            return a.d_ptr.address < b.d_ptr.address
        return a.device < b.device


    @always_inline
    @staticmethod
    fn SizeCompare(read a: BlockDescriptor, read b: BlockDescriptor) -> Bool:
        if a.device == b.device:
            return a.bytes < b.bytes
        return a.device < b.device

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


struct CachingDeviceAllocator(Movable):

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
            power = UInt(8 * size_of[UInt]())
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
    var max_cached_bytes: UInt  # Maximum aggregate cached bytes per device

    var skip_cleanup: Bool  # Whether or not to skip a call to FreeAllCached() when destructor is called.  (The CUDA runtime may have already shut down for statically declared allocators)
    var debug: Bool  # Whether or not to print (de)allocation events to stdout

    var cached_bytes: GpuCachedBytes  # Map of device ordinal to aggregate cached bytes on that device
    var cached_blocks: Self.CachedBlocks  # Set of cached device allocations available for reuse
    var live_blocks: Self.BusyBlocks  # Set of live device allocations currently in use

    var alloc_runtime: CUDARuntime  # Isolated runtime for internal event bookkeeping
    var alloc_state: _AllocateDeviceState  # Isolated device allocation state for pool blocks

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
        max_bin: UInt = Self.INVALID_BIN,
        max_cached_bytes: UInt = Self.INVALID_SIZE,
        skip_cleanup: Bool = False,
        debug: Bool = False
    ):
        self.mutex = BlockingSpinLock()
        self.bin_growth = bin_growth
        self.min_bin = min_bin
        self.max_bin = max_bin
        self.min_bin_bytes = CachingDeviceAllocator.IntPow(bin_growth, min_bin)
        self.max_bin_bytes = CachingDeviceAllocator.IntPow(bin_growth, max_bin)
        self.max_cached_bytes = max_cached_bytes
        self.skip_cleanup = skip_cleanup
        self.debug = debug
        self.cached_bytes = GpuCachedBytes()
        self.cached_blocks = Self.CachedBlocks()
        self.live_blocks = Self.BusyBlocks()
        self.alloc_runtime = CUDARuntime()
        self.alloc_state = _AllocateDeviceState()

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
        self.min_bin_bytes = CachingDeviceAllocator.IntPow(
            self.bin_growth, self.min_bin
        )
        self.max_bin_bytes = CachingDeviceAllocator.IntPow(
            self.bin_growth, self.max_bin
        )
        self.max_cached_bytes = (self.max_bin_bytes * 3) - 1
        self.skip_cleanup = skip_cleanup
        self.debug = debug
        self.cached_bytes = GpuCachedBytes()
        self.cached_blocks = Self.CachedBlocks()
        self.live_blocks = Self.BusyBlocks()
        self.alloc_runtime = CUDARuntime()
        self.alloc_state = _AllocateDeviceState()

    fn __moveinit__(out self, deinit take: Self):
        self.mutex = BlockingSpinLock()
        self.bin_growth = take.bin_growth
        self.min_bin = take.min_bin
        self.max_bin = take.max_bin
        self.min_bin_bytes = take.min_bin_bytes
        self.max_bin_bytes = take.max_bin_bytes
        self.max_cached_bytes = take.max_cached_bytes
        self.skip_cleanup = take.skip_cleanup
        self.debug = take.debug
        self.cached_bytes = take.cached_bytes^
        self.cached_blocks = take.cached_blocks^
        self.live_blocks = take.live_blocks^
        self.alloc_runtime = take.alloc_runtime^
        self.alloc_state = take.alloc_state^

    #/**
    # * \brief Sets the limit on the number bytes this allocator is allowed to cache per device.
    # *
    # * Changing the ceiling of cached bytes does not cause any allocations (in-use or
    # * cached-in-reserve) to be freed.  See \p FreeAllCached().
    # */
    fn SetMaxCachedBytes(mut self, max_cached_bytes: UInt) -> cudaError_t:
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
        return cudaSuccess

    #/**
    # * \brief Provides a suitable allocation of device memory for the given size on the specified device.
    # *
    # * Once freed, the allocation becomes available immediately for reuse within the \p active_stream
    # * with which it was associated with during allocation, and it becomes available for reuse within other
    # * streams when all prior work submitted to \p active_stream has completed.
    # */
    fn DeviceAllocate(
        mut self,
        mut device: Int,
        out d_ptr: UnsafePointer[UInt8, MutAnyOrigin],
        bytes: UInt,
        active_stream: CUDAStreamType = cudaStreamDefault
    ) raises -> cudaError_t:
        # CMS: use RAII instead of (un)locking explicitly
        d_ptr = UnsafePointer[UInt8, MutAnyOrigin]()
        var entrypoint_device = Self.INVALID_DEVICE_ORDINAL
        var error: cudaError_t = cudaSuccess

        if device == Self.INVALID_DEVICE_ORDINAL:
            # CMS: throw exception on error

            error = cudaGetDevice(entrypoint_device)
            # if error != cudaSuccess:
            #     return error
            device = entrypoint_device

        # Create a block descriptor for the requested allocation
        var found = False
        var search_key = BlockDescriptor(device)
        search_key.bytesRequested = bytes
        search_key.associated_stream = active_stream
        CachingDeviceAllocator.NearestPowerOf(
            search_key.bin, search_key.bytes, self.bin_growth, bytes
        )

        if search_key.bin > self.max_bin:
            # Bin is greater than our maximum bin: allocate the request
            # exactly and give out-of-bounds bin.  It will not be cached
            # for reuse when returned.
            search_key.bin = Self.INVALID_BIN
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
                    (self.cached_blocks[block_itr].device == device) and
                    (self.cached_blocks[block_itr].bin == search_key.bin)
                ):
                    # To prevent races with reusing blocks returned by the host but still
                    # in use by the device, only consider cached blocks that are
                    # either (from the active stream) or (from an idle stream)
                    if (
                        (active_stream == self.cached_blocks[block_itr].associated_stream) or
                        (cudaEventQuery(self.cached_blocks[block_itr].ready_event) != cudaErrorNotReady)
                    ):
                        # Reuse existing cache block.  Insert into live blocks.
                        found = True
                        search_key = self.cached_blocks[block_itr]
                        search_key.associated_stream = active_stream
                        self.live_blocks.insert(search_key)

                        # Remove from free blocks
                        var totals = self.cached_bytes.get_or(device, TotalBytes())
                        totals.free -= search_key.bytes
                        totals.live += search_key.bytes
                        totals.liveRequested += search_key.bytesRequested
                        self.cached_bytes[device] = totals

                        if self.debug:
                            print(
                                "\tDevice "
                                + String(device)
                                + " reused cached block at "
                                + String(search_key.d_ptr.address)
                                + " ("
                                + String(search_key.bytes)
                                + " bytes) for stream "
                                + String(search_key.associated_stream)
                                + ", event "
                                + String(search_key.ready_event.event_id)
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
            # No need to replicate lines 419 - 424 from cpp as 
            # Mojo doesnt need to switch device before allocation
            #the device id is passed into the allocation function 


            # Attempt to allocate
            try:
                search_key.d_ptr = self.alloc_state.allocate_device(
                    Int32(device),
                    search_key.bytes,
                    cudaStreamDefault
                )
                error = cudaSuccess
            except e:
                error = cudaErrorMemoryAllocation

            if error == cudaErrorMemoryAllocation:
                # The allocation attempt failed: free all cached blocks on device and retry
                if self.debug:
                    print(
                        "\tDevice "
                        + String(device)
                        + " failed to allocate "
                        + String(search_key.bytes)
                        + " bytes for stream "
                        + String(search_key.associated_stream)
                        + ", retrying after freeing cached allocations"
                    )

                error = cudaSuccess

                # Iterate the range of free blocks on the same device
                with BlockingScopedLock(self.mutex):
                    var free_key = BlockDescriptor(device)
                    var block_itr = self.cached_blocks.lower_bound(free_key)

                    while (
                        (block_itr != self.cached_blocks.__len__()) and
                        (self.cached_blocks[block_itr].device == device)
                    ):
                        var block = self.cached_blocks[block_itr]

                        # Free device memory and destroy stream event.

                        # the mojo implemetation of cudaFree and it doesnt
                        # return an error
                        self.alloc_state.free_device(
                            Int32(device),
                            block.d_ptr,
                            cudaStreamDefault
                        )
                        error = cudaEventDestroy(block.ready_event)
                        if error != cudaSuccess:
                            break

                        # Reduce balance and erase entry
                        # Taking TotalBytes as defualt 
                        var totals = self.cached_bytes.get_or(device, TotalBytes())
                        totals.free -= block.bytes
                        self.cached_bytes[device] = totals

                        if self.debug:
                            print(
                                "\tDevice "
                                + String(device)
                                + " freed "
                                + String(block.bytes)
                                + " bytes.\n\t\t  "
                                + String(self.cached_blocks.__len__())
                                + " available blocks cached ("
                                + String(totals.free)
                                + " bytes), "
                                + String(self.live_blocks.__len__())
                                + " live blocks ("
                                + String(totals.live)
                                + " bytes) outstanding."
                            )

                        _ = self.cached_blocks.erase_at(block_itr)

                        block_itr += 1

                if error != cudaSuccess:
                    return error

                # Try to allocate again
                try:
                    search_key.d_ptr = self.alloc_state.allocate_device(
                        Int32(device),
                        search_key.bytes,
                        cudaStreamDefault
                    )
                    error = cudaSuccess
                except e:
                    error = cudaErrorMemoryAllocation
                    return cudaErrorMemoryAllocation


            # Create ready event
            # NOTE this is temporary and its not actually doing
            # Anything with the flags
            error = cudaEventCreateWithFlags(
                search_key.ready_event,
                cudaEventDisableTiming,
                self.alloc_runtime
            )
            if error != cudaSuccess:
                return error

            # Insert into live blocks
            with BlockingScopedLock(self.mutex):
                self.live_blocks.insert(search_key)
                var totals = self.cached_bytes.get_or(device, TotalBytes())
                totals.live += search_key.bytes
                totals.liveRequested += search_key.bytesRequested
                self.cached_bytes[device] = totals

            if self.debug:
                print(
                    "\tDevice "
                    + String(device)
                    + " allocated new device block at "
                    + String(search_key.d_ptr.address)
                    + " ("
                    + String(search_key.bytes)
                    + " bytes associated with stream "
                    + String(search_key.associated_stream)
                    + ", event "
                    + String(search_key.ready_event.event_id)
                    + ")."
                )

        # Copy device pointer to output parameter
        d_ptr = search_key.d_ptr

        if self.debug:
            var totals = self.cached_bytes.get_or(device, TotalBytes())
            print(
                "\t\t"
                + String(self.cached_blocks.__len__())
                + " available blocks cached ("
                + String(totals.free)
                + " bytes), "
                + String(self.live_blocks.__len__())
                + " live blocks outstanding("
                + String(totals.live)
                + " bytes)."
            )

        return error

    #/**
    # * \brief Provides a suitable allocation of device memory for the given size on the current device.
    # *
    # * Once freed, the allocation becomes available immediately for reuse within the \p active_stream
    # * with which it was associated with during allocation, and it becomes available for reuse within other
    # * streams when all prior work submitted to \p active_stream has completed.
    # */
    fn DeviceAllocate(
        mut self,
        out d_ptr: UnsafePointer[UInt8, MutAnyOrigin],
        bytes: UInt,
        active_stream: CUDAStreamType = cudaStreamDefault
    ) raises -> cudaError_t:
        return self.DeviceAllocate(
            Self.INVALID_DEVICE_ORDINAL,
            d_ptr,
            bytes,
            active_stream
        )

    #/**
    # * \brief Frees a live allocation of device memory on the specified device, returning it to the allocator.
    # *
    # * Once freed, the allocation becomes available immediately for reuse within the \p active_stream
    # * with which it was associated with during allocation, and it becomes available for reuse within other
    # * streams when all prior work submitted to \p active_stream has completed.
    # */
    fn DeviceFree(
        mut self,
        mut device: Int,
        d_ptr: UnsafePointer[UInt8, MutAnyOrigin]
    ) raises -> cudaError_t:
        var entrypoint_device = Self.INVALID_DEVICE_ORDINAL
        var error: cudaError_t = cudaSuccess
        var recached = False
        var search_key = BlockDescriptor(d_ptr, device)

        if device == Self.INVALID_DEVICE_ORDINAL:
            error = cudaGetDevice(entrypoint_device)
            if error != cudaSuccess:
                return error
            device = entrypoint_device
        # search_key.device = device



        with BlockingScopedLock(self.mutex):
            var block_itr = self.live_blocks.find(search_key)
            if block_itr != -1:
                search_key = self.live_blocks[block_itr]
                _ = self.live_blocks.erase_at(block_itr)

                var totals = self.cached_bytes.get_or(device, TotalBytes())
                # will be later used to update the cached_bytes
                totals.live -= search_key.bytes
                totals.liveRequested -= search_key.bytesRequested

                # Keep the returned allocation if bin is valid and we won't exceed the max cached threshold.
                if (
                    (search_key.bin != Self.INVALID_BIN) and
                    (totals.free + search_key.bytes <= self.max_cached_bytes)
                ):
                    recached = True
                    self.cached_blocks.insert(search_key)
                    totals.free += search_key.bytes

                    if self.debug:
                        print(
                            "\tDevice "
                            + String(device)
                            + " returned "
                            + String(search_key.bytes)
                            + " bytes at "
                            + String(d_ptr.address)
                            + " from associated stream "
                            + String(search_key.associated_stream)
                            + ", event "
                            + String(search_key.ready_event.event_id)
                            + ".\n\t\t "
                            + String(self.cached_blocks.__len__())
                            + " available blocks cached ("
                            + String(totals.free)
                            + " bytes), "
                            + String(self.live_blocks.__len__())
                            + " live blocks outstanding. ("
                            + String(totals.live)
                            + " bytes)"
                        )

                self.cached_bytes[device] = totals

            if recached:
                # Insert the ready event in the associated stream.
                error = cudaEventRecord(search_key.ready_event, search_key.associated_stream)
                if error != cudaSuccess:
                    return error

        if not recached:
            # Free the allocation from the runtime and cleanup the event.
            self.alloc_state.free_device(
                Int32(device),
                d_ptr,
                cudaStreamDefault
            )
            error = cudaEventDestroy(search_key.ready_event)
            if error != cudaSuccess:
                return error

            if self.debug:
                var totals = self.cached_bytes.get_or(device, TotalBytes())
                print(
                    "\tDevice "
                    + String(device)
                    + " freed "
                    + String(search_key.bytes)
                    + " bytes at "
                    + String(d_ptr.address)
                    + " from associated stream "
                    + String(search_key.associated_stream)
                    + ", event "
                    + String(search_key.ready_event.event_id)
                    + ".\n\t\t  "
                    + String(self.cached_blocks.__len__())
                    + " available blocks cached ("
                    + String(totals.free)
                    + " bytes), "
                    + String(self.live_blocks.__len__())
                    + " live blocks ("
                    + String(totals.live)
                    + " bytes) outstanding."
                )

        return error

    #/**
    # * \brief Frees a live allocation of device memory on the current device, returning it to the allocator.
    # */
    fn DeviceFree(
        mut self,
        d_ptr: UnsafePointer[UInt8, MutAnyOrigin]
    ) raises -> cudaError_t:
        return self.DeviceFree(Self.INVALID_DEVICE_ORDINAL, d_ptr)

    #/**
    # * \brief Frees all cached device allocations on all devices.
    # */
    fn FreeAllCached(mut self) raises -> cudaError_t:
        var error: cudaError_t = cudaSuccess

        with BlockingScopedLock(self.mutex):
            while self.cached_blocks.__len__() > 0:
                var begin = self.cached_blocks[0]

                self.alloc_state.free_device(
                    Int32(begin.device),
                    begin.d_ptr,
                    cudaStreamDefault
                )
                error = cudaEventDestroy(begin.ready_event)
                if error != cudaSuccess:
                    return error

                var totals = self.cached_bytes.get_or(begin.device, TotalBytes())
                totals.free -= begin.bytes
                self.cached_bytes[begin.device] = totals

                if self.debug:
                    print(
                        "\tDevice "
                        + String(begin.device)
                        + " freed "
                        + String(begin.bytes)
                        + " bytes.\n\t\t  "
                        + String(self.cached_blocks.__len__())
                        + " available blocks cached ("
                        + String(totals.free)
                        + " bytes), "
                        + String(self.live_blocks.__len__())
                        + " live blocks ("
                        + String(totals.live)
                        + " bytes) outstanding."
                    )

                _ = self.cached_blocks.erase_at(0)

        return error

    #/**
    # * \brief Snapshot of cache allocation status by device.
    # */
    fn CacheStatus(mut self) -> GpuCachedBytes:
        with BlockingScopedLock(self.mutex):
            return self.cached_bytes


    #/**
    # * \brief Destructor.
    # */
    fn __del__(var self):
        if not self.skip_cleanup:
            try:
                _ = self.FreeAllCached()
            except e:
                if self.debug:
                    print("CachingDeviceAllocator cleanup failed:", e)
