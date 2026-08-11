from MojoBridge.DTypes import Typeable


struct EDPutTokenT[T: Typeable](Copyable, Defaultable, Movable, Typeable, TrivialRegisterPassable):
    alias s_uninitializedValue = 0xFFFFFFFF
    var m_value: UInt

    fn __init__(out self):
        self.m_value = Self.s_uninitializedValue

    @always_inline
    fn __init__(out self, var iOther: EDPutToken):
        self.m_value = iOther.m_value

    @always_inline
    fn __init__[O: Typeable](out self, iValue: UInt):
        constrained[
            O.dtype() == "ProductRegistry",
            "Only the product registry can hand tokens",
        ]()
        self.m_value = iValue

    @always_inline
    fn index(self) -> UInt:
        return self.m_value

    @always_inline
    fn isUninitialized(self) -> Bool:
        return self.m_value == Self.s_uninitializedValue

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "EDPutTokenT[" + Self.T.dtype() + "]"


struct EDPutToken(Copyable, Defaultable, Movable, Typeable, TrivialRegisterPassable):
    alias s_uninitializedValue = 0xFFFFFFFF
    var m_value: UInt

    @always_inline
    fn __init__(out self):
        self.m_value = Self.s_uninitializedValue

    @always_inline
    fn __init__[T: Typeable, //](out self, var iOther: EDPutTokenT[T]):
        self.m_value = iOther.m_value

    @always_inline
    fn __init__[O: Typeable](out self, iValue: UInt):
        constrained[
            O.dtype() == "ProductRegistry",
            "Only the product registry can hand tokens",
        ]()
        self.m_value = iValue

    @always_inline
    fn index(self) -> UInt:
        return self.m_value

    @always_inline
    fn isUninitialized(self) -> Bool:
        return self.m_value == Self.s_uninitializedValue

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "EDPutToken"
