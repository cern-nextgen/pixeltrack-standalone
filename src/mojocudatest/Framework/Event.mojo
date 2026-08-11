from Framework.EDGetToken import EDGetTokenT
from Framework.EDPutToken import EDPutTokenT
from Framework.ProductRegistry import ProductRegistry
from MojoBridge.DTypes import Typeable

alias StreamID = Int32


struct WrapperBase(Copyable, Defaultable, ImplicitlyCopyable, Movable, Typeable):
    var _ptr: UnsafePointer[NoneType, MutAnyOrigin]

    @always_inline
    fn __init__(out self):
        self._ptr = UnsafePointer[NoneType, MutAnyOrigin]()

    @always_inline
    fn __copyinit__(out self, copy: Self):
        self._ptr = copy._ptr

    @always_inline
    fn __moveinit__(out self, var take: Self):
        self._ptr = take._ptr
        take._ptr = UnsafePointer[NoneType, MutAnyOrigin]()

    @always_inline
    fn product(self) -> UnsafePointer[NoneType, MutAnyOrigin]:
        return self._ptr

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "WrapperBase"


fn det_blank(mut wrapper: WrapperBase):
    pass


struct Wrapper[T: Typeable & Movable & ImplicitlyDestructible](Movable, Typeable):
    var _ptr: UnsafePointer[Self.T, MutAnyOrigin]

    @always_inline
    fn __init__(out self, var obj: Self.T):
        self._ptr = alloc[Self.T](1)
        __get_address_as_uninit_lvalue(self._ptr.address) = obj^

    @always_inline
    fn delete(self):
        if self._ptr == UnsafePointer[Self.T, MutAnyOrigin]():
            return
        self._ptr.free()

    @always_inline
    fn __moveinit__(out self, var take: Self):
        self._ptr = take._ptr
        take._ptr = UnsafePointer[Self.T, MutAnyOrigin]()

    @always_inline
    fn product(self) -> UnsafePointer[Self.T, MutAnyOrigin]:
        return self._ptr

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "Wrapper[" + Self.T.dtype() + "]"


struct Event(Defaultable, Movable, Typeable):
    var _streamId: StreamID
    var _eventId: Int32
    var _products: List[WrapperBase]
    var _dets: List[fn (mut WrapperBase)]

    @always_inline
    fn __init__(out self):
        self._streamId = 0
        self._eventId = 0
        self._products = []
        self._dets = []

    @always_inline
    fn __init__(
        out self,
        var streamId: Int32,
        var eventId: Int32,
        ref reg: ProductRegistry,
    ):
        self._streamId = streamId
        self._eventId = eventId
        self._products = List[WrapperBase](
            length=reg.__len__(), fill=WrapperBase()
        )
        self._dets = List[fn (mut WrapperBase)](
            length=reg.__len__(), fill=det_blank
        )

    fn __del__(var self):
        for i in range(self._products.__len__()):
            self._dets[i](self._products[i])

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._streamId = take._streamId
        self._eventId = take._eventId
        self._products = take._products^
        self._dets = take._dets^

    @always_inline
    fn streamID(self) -> StreamID:
        return self._streamId

    @always_inline
    fn eventID(self) -> Int32:
        return self._eventId

    fn get[
        T: Typeable & Movable & ImplicitlyDestructible
    ](self, ref token: EDGetTokenT[T]) -> ref [self._products] T:
        return rebind[Wrapper[T]](self._products[token.index()]).product()[]

    fn emplace[
        T: Typeable & Movable & ImplicitlyDestructible
    ](mut self, ref token: EDPutTokenT[T], var prod: T):
        @always_inline
        fn det[T: Typeable & Movable & ImplicitlyDestructible](mut wrapper: WrapperBase):
            rebind[Wrapper[T]](wrapper).delete()

        self._products[token.index()] = rebind[WrapperBase](Wrapper[T](prod^))
        self._dets[token.index()] = det[T]

    fn put[
        T: Typeable & Movable & ImplicitlyDestructible
    ](mut self, ref token: EDPutTokenT[T], var prod: T):
        self.emplace[T](token, prod^)

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "Event"
