from memory import OwnedPointer
from std.sys.info import size_of

from CUDACompat import CUDAStreamType, cudaStreamDefault
from allocate_host import _AllocateHostState, _max_allocation_size


alias cudaStream_t = CUDAStreamType


# Holds the raw pinned-host pointer and owns its lifetime.
struct _HostAllocation[T: AnyType](Movable, Defaultable):
    var ptr: UnsafePointer[Self.T, MutAnyOrigin]
    var state: UnsafePointer[_AllocateHostState, MutAnyOrigin]

    @always_inline
    fn __init__(out self):
        self.ptr = UnsafePointer[Self.T, MutAnyOrigin]()
        self.state = UnsafePointer[_AllocateHostState, MutAnyOrigin]()

    @always_inline
    fn __init__(out self, ptr: UnsafePointer[Self.T, MutAnyOrigin], state: UnsafePointer[_AllocateHostState, MutAnyOrigin]):
        self.ptr = ptr
        self.state = state

    @always_inline
    fn __moveinit__(out self, var take: Self):
        self.ptr = take.ptr
        self.state = take.state
        take.ptr = UnsafePointer[Self.T, MutAnyOrigin]()
        take.state = UnsafePointer[_AllocateHostState, MutAnyOrigin]()

    fn __del__(var self):
        if self.ptr != UnsafePointer[Self.T, MutAnyOrigin]() and self.state != UnsafePointer[_AllocateHostState, MutAnyOrigin]():
            self.state[].free_host_raw(self.ptr.bitcast[UInt8]())

    @always_inline
    fn get(self) -> UnsafePointer[Self.T, MutAnyOrigin]:
        return self.ptr

    @always_inline
    fn release(mut self) -> UnsafePointer[Self.T, MutAnyOrigin]:
        var released = self.ptr
        self.ptr = UnsafePointer[Self.T, MutAnyOrigin]()
        self.state = UnsafePointer[_AllocateHostState, MutAnyOrigin]()
        return released

    @always_inline
    fn reset(mut self, ptr: UnsafePointer[Self.T, MutAnyOrigin] = UnsafePointer[Self.T, MutAnyOrigin]()):
        if self.ptr != UnsafePointer[Self.T, MutAnyOrigin]() and self.state != UnsafePointer[_AllocateHostState, MutAnyOrigin]():
            self.state[].free_host_raw(self.ptr.bitcast[UInt8]())
        self.ptr = ptr


# Equivalent to cms::cuda::host::unique_ptr<T>
alias unique_ptr[T: AnyType] = OwnedPointer[_HostAllocation[T]]


fn make_host_unique[T: AnyType](mut state: _AllocateHostState, stream: cudaStream_t = cudaStreamDefault) raises -> unique_ptr[T]:
    var max_size = _max_allocation_size()
    var nbytes = UInt(size_of[T]())
    if nbytes > max_size:
        raise Error("Tried to allocate " + String(nbytes) + " bytes, but the allocator maximum is " + String(max_size))
    var mem = state.allocate_host_raw(nbytes, stream)
    return unique_ptr[T](_HostAllocation[T](mem.bitcast[T](), UnsafePointer(to=state)))


fn make_host_unique[T: AnyType](
    n: UInt,
    mut state: _AllocateHostState,
    stream: cudaStream_t = cudaStreamDefault,
) raises -> unique_ptr[T]:
    var max_size = _max_allocation_size()
    var nbytes = n * UInt(size_of[T]())
    if nbytes > max_size:
        raise Error("Tried to allocate " + String(nbytes) + " bytes, but the allocator maximum is " + String(max_size))
    var mem = state.allocate_host_raw(nbytes, stream)
    return unique_ptr[T](_HostAllocation[T](mem.bitcast[T](), UnsafePointer(to=state)))


fn make_host_unique_uninitialized[T: AnyType](
    mut state: _AllocateHostState,
    stream: cudaStream_t = cudaStreamDefault,
) raises -> unique_ptr[T]:
    var max_size = _max_allocation_size()
    var nbytes = UInt(size_of[T]())
    if nbytes > max_size:
        raise Error("Tried to allocate " + String(nbytes) + " bytes, but the allocator maximum is " + String(max_size))
    var mem = state.allocate_host_raw(nbytes, stream)
    return unique_ptr[T](_HostAllocation[T](mem.bitcast[T](), UnsafePointer(to=state)))


fn make_host_unique_uninitialized[T: AnyType](
    n: UInt,
    mut state: _AllocateHostState,
    stream: cudaStream_t = cudaStreamDefault,
) raises -> unique_ptr[T]:
    var max_size = _max_allocation_size()
    var nbytes = n * UInt(size_of[T]())
    if nbytes > max_size:
        raise Error("Tried to allocate " + String(nbytes) + " bytes, but the allocator maximum is " + String(max_size))
    var mem = state.allocate_host_raw(nbytes, stream)
    return unique_ptr[T](_HostAllocation[T](mem.bitcast[T](), UnsafePointer(to=state)))
