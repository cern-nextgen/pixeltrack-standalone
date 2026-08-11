from collections import Set

from Framework.EDGetToken import EDGetTokenT
from Framework.EDPutToken import EDPutTokenT
from MojoBridge.DTypes import Typeable


@fieldwise_init
struct Indices(Copyable, Movable, Typeable, TrivialRegisterPassable):
    var _moduleIndex: UInt
    var _productIndex: UInt

    @always_inline
    fn moduleIndex(self) -> UInt:
        return self._moduleIndex

    @always_inline
    fn productIndex(self) -> UInt:
        return self._productIndex

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "Indices"


struct ProductRegistry(Movable, Sized, Typeable):
    alias kSourceIndex: Int = 0
    var _currentModuleIndex: Int32
    var _consumedModules: Set[UInt]
    var _typeToIndex: Dict[String, Indices]

    @always_inline
    fn __init__(out self):
        self._currentModuleIndex = Self.kSourceIndex
        self._consumedModules = Set[UInt]()
        self._typeToIndex = Dict[String, Indices]()

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._currentModuleIndex = take._currentModuleIndex
        self._consumedModules = take._consumedModules^
        self._typeToIndex = take._typeToIndex^

    fn produces[T: Typeable](mut self) raises -> EDPutTokenT[T]:
        if T.dtype() in self._typeToIndex:
            raise "RuntimeError: Product of type " + T.dtype() + " already exists."
        var ind = self.__len__()
        self._typeToIndex[T.dtype()] = Indices(
            UInt(self._currentModuleIndex), ind
        )
        return EDPutTokenT[T].__init__[Self](ind)

    fn consumes[T: Typeable](mut self) raises -> EDGetTokenT[T]:
        if T.dtype() not in self._typeToIndex:
            raise "RuntimeError: Product of type " + T.dtype() + " is not produced."
        var item = self._typeToIndex[T.dtype()]
        self._consumedModules.add(item.moduleIndex())
        return EDGetTokenT[T].__init__[Self](item.productIndex())

    # internal interface
    fn beginModuleConstruction(mut self, i: Int32):
        self._currentModuleIndex = i
        self._consumedModules.clear()

    fn consumedModules(self) -> ref [self._consumedModules] Set[UInt]:
        return self._consumedModules

    fn __len__(self) -> Int:
        return self._typeToIndex.__len__()

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "ProductRegistry"
