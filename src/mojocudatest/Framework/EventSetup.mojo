from MojoBridge.DTypes import Typeable


struct ESWrapperBase(Copyable, Defaultable, ImplicitlyCopyable, Movable, Typeable):
    var _ptr: UnsafePointer[NoneType, MutAnyOrigin]

    @always_inline
    fn __init__(out self):
        self._ptr = UnsafePointer[NoneType, MutAnyOrigin]()

    @always_inline
    fn product(self) -> UnsafePointer[NoneType, MutAnyOrigin]:
        return self._ptr

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "ESWrapperBase"


fn det_blank(mut wrapper: ESWrapperBase):
    pass


struct ESWrapper[T: Typeable & Movable & ImplicitlyDestructible](Movable, Typeable):
    var _ptr: UnsafePointer[Self.T, MutAnyOrigin]

    @always_inline
    fn __init__(out self, var obj: Self.T):
        self._ptr = alloc[Self.T](1)
        __get_address_as_uninit_lvalue(self._ptr.address) = obj^

    @always_inline
    fn __moveinit__(out self, var take: Self):
        self._ptr = take._ptr

    @always_inline
    fn delete(self):
        self._ptr.destroy_pointee()
        self._ptr.free()

    @always_inline
    fn product(self) -> UnsafePointer[Self.T, MutAnyOrigin]:
        return self._ptr

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "ESWrapper[" + Self.T.dtype() + "]"


struct EventSetup(Defaultable, Movable, Typeable):
    var _typeToProduct: Dict[String, ESWrapperBase]
    var _dets: Dict[String, fn (mut ESWrapperBase)]

    @always_inline
    fn __init__(out self):
        self._typeToProduct = Dict[String, ESWrapperBase]()
        self._dets = Dict[String, fn (mut ESWrapperBase)]()

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._typeToProduct = take._typeToProduct^
        self._dets = take._dets^

    fn __del__(var self):
        var keys = List[String]()
        for k in self._typeToProduct.keys():
            keys.append(k)
        for k in keys:
            try:
                var det_fn = self._dets[k]
                det_fn(self._typeToProduct[k])
            except e:
                print(
                    (
                        "Error in Framework/EventSetup.mojo: Failed to delete"
                        " object with key"
                    ),
                    k,
                    "in EventSetup with error",
                    e,
                )

    fn put[T: Typeable & Movable & ImplicitlyDestructible](mut self, var prod: T) raises:
        @always_inline
        fn det[T: Typeable & Movable & ImplicitlyDestructible](mut wrapper: ESWrapperBase):
            rebind[ESWrapper[T]](wrapper).delete()

        if T.dtype() in self._typeToProduct:
            raise "RuntimeError: Product of type " + T.dtype() + " already exists."
        self._typeToProduct[T.dtype()] = rebind[ESWrapperBase](
            ESWrapper[T](prod^)
        )
        self._dets[T.dtype()] = det[T]

    fn get[T: Typeable & Movable & ImplicitlyDestructible](self) raises -> ref [self._typeToProduct] T:
        if T.dtype() not in self._typeToProduct:
            raise "RuntimeError: Product of type " + T.dtype() + " is not produced."
        return rebind[ESWrapper[T]](self._typeToProduct[T.dtype()]).product()[]

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "EventSetup"
