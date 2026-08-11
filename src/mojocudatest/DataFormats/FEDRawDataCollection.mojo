from DataFormats.FEDRawData import FEDRawData
from DataFormats.FEDNumbering import FEDNumbering
from MojoBridge.DTypes import Typeable


struct FEDRawDataCollection(Copyable, Defaultable, ImplicitlyCopyable, Movable, Typeable):
    var _data: List[FEDRawData]

    @always_inline
    fn __init__(out self):
        self._data = List[FEDRawData](
            length=FEDNumbering.lastFEDId() + 1, fill=FEDRawData()
        )

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._data = take._data^

    @always_inline
    fn __copyinit__(out self, copy: Self):
        self._data = List[FEDRawData]()
        for i in range(copy._data.__len__()):
            self._data.append(copy._data[i])

    @always_inline
    fn FEDData(ref self, fedid: Int) -> ref [self._data] FEDRawData:
        return self._data[fedid]

    @always_inline
    fn swap(mut self, mut other: Self):
        swap(self._data, other._data)

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "FEDRawDataCollection"


# swap is a library function
