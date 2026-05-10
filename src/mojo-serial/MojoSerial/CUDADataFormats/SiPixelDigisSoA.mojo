from memory import OwnedPointer

from MojoSerial.MojoBridge.DTypes import SizeType, Typeable


@fieldwise_init
struct DeviceConstView(Defaultable, Movable, Typeable):
    var _xx: UnsafePointer[UInt16]
    var _yy: UnsafePointer[UInt16]
    var _adc: UnsafePointer[UInt16]
    var _moduleInd: UnsafePointer[UInt16]
    var _clus: UnsafePointer[Int32]

    @always_inline
    fn __init__(out self):
        self._xx = UnsafePointer[UInt16]()
        self._yy = UnsafePointer[UInt16]()
        self._adc = UnsafePointer[UInt16]()
        self._moduleInd = UnsafePointer[UInt16]()
        self._clus = UnsafePointer[Int32]()

    @always_inline
    fn xx(self, i: Int) -> UInt16:
        return self._xx[i]

    @always_inline
    fn yy(self, i: Int) -> UInt16:
        return self._yy[i]

    @always_inline
    fn adc(self, i: Int) -> UInt16:
        return self._adc[i]

    @always_inline
    fn moduleInd(self, i: Int) -> UInt16:
        return self._moduleInd[i]

    @always_inline
    fn clus(self, i: Int) -> Int32:
        return self._clus[i]

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "DeviceConstView"


struct SiPixelDigisSoA(Defaultable, Movable, Typeable):
    var xx_d: OwnedPointer[List[UInt16]]  # local coordinates of each pixel
    var yy_d: OwnedPointer[List[UInt16]]
    var adc_d: OwnedPointer[List[UInt16]]  # ADC of each pixel
    var moduleInd_d: OwnedPointer[List[UInt16]]  # module id of each pixel
    var clus_d: OwnedPointer[List[Int32]]  # cluster id of each pixel
    var view_d: OwnedPointer[DeviceConstView]  # "me" pointer

    # These are for CPU output; should we (eventually) place them to a
    # separate product?
    var pdigi_d: OwnedPointer[List[UInt32]]
    var rawIdArr_d: OwnedPointer[List[UInt32]]

    var nModules_h: UInt32
    var nDigis_h: UInt32

    @always_inline
    fn __init__(out self):
        self.xx_d = OwnedPointer(List[UInt16]())
        self.yy_d = OwnedPointer(List[UInt16]())
        self.adc_d = OwnedPointer(List[UInt16]())
        self.moduleInd_d = OwnedPointer(List[UInt16]())
        self.clus_d = OwnedPointer(List[Int32]())
        self.view_d = OwnedPointer(DeviceConstView())

        self.pdigi_d = OwnedPointer(List[UInt32]())
        self.rawIdArr_d = OwnedPointer(List[UInt32]())

        self.nModules_h = 0
        self.nDigis_h = 0

    @always_inline
    fn __init__(out self, maxFedWords: SizeType):
        self.xx_d = OwnedPointer(List[UInt16](length=UInt(maxFedWords), fill=0))
        self.yy_d = OwnedPointer(List[UInt16](length=UInt(maxFedWords), fill=0))
        self.adc_d = OwnedPointer(
            List[UInt16](length=UInt(maxFedWords), fill=0)
        )
        self.moduleInd_d = OwnedPointer(
            List[UInt16](length=UInt(maxFedWords), fill=0)
        )
        self.clus_d = OwnedPointer(
            List[Int32](length=UInt(maxFedWords), fill=0)
        )
        self.view_d = OwnedPointer(
            DeviceConstView(
                self.xx_d[].unsafe_ptr(),
                self.yy_d[].unsafe_ptr(),
                self.adc_d[].unsafe_ptr(),
                self.moduleInd_d[].unsafe_ptr(),
                self.clus_d[].unsafe_ptr(),
            )
        )

        self.pdigi_d = OwnedPointer(
            List[UInt32](length=UInt(maxFedWords), fill=0)
        )
        self.rawIdArr_d = OwnedPointer(
            List[UInt32](length=UInt(maxFedWords), fill=0)
        )

        self.nModules_h = 0
        self.nDigis_h = 0

    fn __moveinit__(out self, var other: Self):
        self.xx_d = other.xx_d^
        self.yy_d = other.yy_d^
        self.adc_d = other.adc_d^
        self.moduleInd_d = other.moduleInd_d^
        self.clus_d = other.clus_d^

        self.pdigi_d = other.pdigi_d^
        self.rawIdArr_d = other.rawIdArr_d^

        self.nModules_h = other.nModules_h
        self.nDigis_h = other.nDigis_h

        self.view_d = OwnedPointer(
            DeviceConstView(
                self.xx_d[].unsafe_ptr(),
                self.yy_d[].unsafe_ptr(),
                self.adc_d[].unsafe_ptr(),
                self.moduleInd_d[].unsafe_ptr(),
                self.clus_d[].unsafe_ptr(),
            )
        )

    @always_inline
    fn view(self) -> UnsafePointer[DeviceConstView, mut=False]:
        return self.view_d.unsafe_ptr()

    @always_inline
    fn setNModulesDigis(mut self, nModules: UInt32, nDigis: UInt32):
        self.nModules_h = nModules
        self.nDigis_h = nDigis

    @always_inline
    fn nModules(self) -> UInt32:
        return self.nModules_h

    @always_inline
    fn nDigis(self) -> UInt32:
        return self.nDigis_h

    @always_inline
    fn xx[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt16, mut = origin.mut, origin=origin
    ]:
        return self.xx_d[].unsafe_ptr()

    @always_inline
    fn yy[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt16, mut = origin.mut, origin=origin
    ]:
        return self.yy_d[].unsafe_ptr()

    @always_inline
    fn adc[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt16, mut = origin.mut, origin=origin
    ]:
        return self.adc_d[].unsafe_ptr()

    @always_inline
    fn moduleInd[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt16, mut = origin.mut, origin=origin
    ]:
        return self.moduleInd_d[].unsafe_ptr()

    @always_inline
    fn clus[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        Int32, mut = origin.mut, origin=origin
    ]:
        return self.clus_d[].unsafe_ptr()

    @always_inline
    fn pdigi[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt32, mut = origin.mut, origin=origin
    ]:
        return self.pdigi_d[].unsafe_ptr()

    @always_inline
    fn rawIdArr[
        origin: Origin, //
    ](ref [origin]self) -> UnsafePointer[
        UInt32, mut = origin.mut, origin=origin
    ]:
        return self.rawIdArr_d[].unsafe_ptr()

    @always_inline
    fn c_xx(self) -> UnsafePointer[UInt16, mut=False]:
        return self.xx_d[].unsafe_ptr()

    @always_inline
    fn c_yy(self) -> UnsafePointer[UInt16, mut=False]:
        return self.yy_d[].unsafe_ptr()

    @always_inline
    fn c_adc(self) -> UnsafePointer[UInt16, mut=False]:
        return self.adc_d[].unsafe_ptr()

    @always_inline
    fn c_moduleInd(self) -> UnsafePointer[UInt16, mut=False]:
        return self.moduleInd_d[].unsafe_ptr()

    @always_inline
    fn c_clus(self) -> UnsafePointer[Int32, mut=False]:
        return self.clus_d[].unsafe_ptr()

    @always_inline
    fn c_pdigi(self) -> UnsafePointer[UInt32, mut=False]:
        return self.pdigi_d[].unsafe_ptr()

    @always_inline
    fn c_rawIdArr(self) -> UnsafePointer[UInt32, mut=False]:
        return self.rawIdArr_d[].unsafe_ptr()

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "SiPixelDigisSoA"
