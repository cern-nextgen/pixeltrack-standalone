from SharedStreamPtr import SharedStreamPtr
from SharedEventPtr import SharedEventPtr
from ProductBase import ProductBase
from MojoBridge.DTypes import Typeable


# The purpose of this class is to wrap CUDA data to edm::Event in a
# way which forces correct use of various utilities.
#
# The non-default construction has to be done with cms::cuda::ScopedContext
# (in order to properly register the CUDA event).
#
# The default constructor is needed only for the ROOT dictionary generation.
#
# The CUDA event is in practice needed only for stream-stream
# synchronization, but someone with long-enough lifetime has to own
# it. Here is a somewhat natural place. If overhead is too much, we
# can use them only where synchronization between streams is needed.
struct Product[T: Movable & Typeable & Defaultable](Movable, Typeable):
    var _base: ProductBase
    var data_: Self.T

    fn __init__(out self):
        # Needed only for ROOT dictionary generation
        self._base = ProductBase()
        self.data_ = Self.T()

    fn __init__(
        out self,
        device: Int,
        var stream: SharedStreamPtr,
        var event: SharedEventPtr,
        var data: Self.T,
    ):
        self._base = ProductBase(device, stream^, event^)
        self.data_ = data^

    fn __moveinit__(out self, deinit take: Self):
        self._base = take._base^
        self.data_ = take.data_^

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "Product[" + Self.T.dtype() + "]"
