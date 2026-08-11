from std.memory.arc_pointer import ArcPointer
from os.atomic import Atomic

from CUDACompat import CUDAStreamType, CUDAEventType, cudaEventQuery, cudaSuccess
from MojoBridge.DTypes import cudaError_t
from SharedStreamPtr import SharedStreamPtr
from SharedEventPtr import SharedEventPtr, _EventOwner
from eventWorkHasCompleted import event_work_has_completed


# Mojo: cudaEventSynchronize is not yet mapped — spin on cudaEventQuery instead.
fn _cuda_event_synchronize(event: CUDAEventType):
    while cudaEventQuery(event) != cudaSuccess:
        pass


# Base class for all instantiations of CUDA<T> to hold the
# non-T-dependent members.
struct ProductBase(Movable):
    # The cudaStream_t is really shared among edm::Event products, so
    # using shared_ptr also here
    var stream_: Optional[SharedStreamPtr]
    # shared_ptr because of caching in cms::cuda::EventCache
    var event_: Optional[SharedEventPtr]
    # This flag tells whether the CUDA stream may be reused by a
    # consumer or not. The goal is to have a "chain" of modules to
    # queue their work to the same stream.
    # Mojo: Atomic[DType.uint8] used in place of std::atomic<bool>
    var mayReuseStream_: Atomic[DType.uint8]
    # The CUDA device associated with this product
    var device_: Int

    fn __init__(out self):
        # Needed only for ROOT dictionary generation
        self.stream_ = None
        self.event_ = None
        self.mayReuseStream_ = Atomic[DType.uint8](1)
        self.device_ = -1

    fn __init__(
        out self,
        device: Int,
        var stream: SharedStreamPtr,
        var event: SharedEventPtr,
    ):
        self.stream_ = stream^
        self.event_ = event^
        self.mayReuseStream_ = Atomic[DType.uint8](1)
        self.device_ = device

    fn __moveinit__(out self, deinit take: Self):
        self.stream_ = take.stream_^
        self.event_ = take.event_^
        # Mojo: Atomic is not copyable/movable — read value and construct fresh
        self.mayReuseStream_ = Atomic[DType.uint8](take.mayReuseStream_.load())
        self.device_ = take.device_

    fn __del__(var self):
        # Make sure that the production of the product in the GPU is
        # complete before destructing the product. This is to make sure
        # that the EDM stream does not move to the next event before all
        # asynchronous processing of the current is complete.

        # TODO: a callback notifying a WaitingTaskHolder (or similar)
        # would avoid blocking the CPU, but would also require more work.
        #
        # Intentionally not checking the return value to avoid throwing
        # exceptions. If this call would fail, we should get failures
        # elsewhere as well.
        if self.event_:
            _cuda_event_synchronize(self.event_.value()[].event)

    fn isValid(self) -> Bool:
        return self.stream_ is not None

    fn isAvailable(self) -> Bool:
        # if default-constructed, the product is not available
        if not self.event_:
            return False
        return event_work_has_completed(self.event_.value()[].event)

    fn device(self) -> Int:
        return self.device_

    # cudaStream_t is a pointer to a thread-safe object, for which a
    # mutable access is needed even if the cms::cuda::ScopedContext itself
    # would be const. Therefore it is ok to return a non-const
    # pointer from a const method here.
    fn stream(self) -> CUDAStreamType:
        return self.stream_.value()[]._item.value()

    # cudaEvent_t is a pointer to a thread-safe object, for which a
    # mutable access is needed even if the cms::cuda::ScopedContext itself
    # would be const. Therefore it is ok to return a non-const
    # pointer from a const method here.
    fn event(self) -> CUDAEventType:
        return self.event_.value()[].event

    # The following function is intended to be used only from ScopedContext
    fn streamPtr(self) -> Optional[SharedStreamPtr]:
        return self.stream_

    fn mayReuseStream(mut self) -> Bool:
        # compare_exchange_weak not available in Mojo 0.26.2; fetch_sub is equivalent
        # for this binary flag: first caller decrements 1→0 and gets True.
        return self.mayReuseStream_.fetch_sub(1) == UInt8(1)
