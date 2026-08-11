from sys import sizeof

from MojoBridge.DTypes import Typeable, UChar


@fieldwise_init
@register_passable("trivial")
struct FedtStruct(Copyable, Defaultable, Movable, Typeable):
    var conscheck: UInt32
    var eventsize: UInt32

    @always_inline
    fn __init__(out self):
        self.conscheck = 0
        self.eventsize = 0

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "FedtStruct"


alias FedtType = FedtStruct

alias FED_SLINK_END_MARKER = 0xA

alias FED_TCTRLID_WIDTH = 0x0000000F
alias FED_TCTRLID_SHIFT = 28
alias FED_TCTRLID_MASK = (FED_TCTRLID_WIDTH << FED_TCTRLID_SHIFT)


@always_inline
fn FED_TCTRLID_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_TCTRLID_SHIFT) & FED_TCTRLID_WIDTH


alias FED_EVSZ_WIDTH = 0x00FFFFFF
alias FED_EVSZ_SHIFT = 0
alias FED_EVSZ_MASK = (FED_EVSZ_WIDTH << FED_EVSZ_SHIFT)


@always_inline
fn FED_EVSZ_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_EVSZ_SHIFT) & FED_EVSZ_WIDTH


alias FED_CRCS_WIDTH = 0x0000FFFF
alias FED_CRCS_SHIFT = 16
alias FED_CRCS_MASK = (FED_CRCS_WIDTH << FED_CRCS_SHIFT)


@always_inline
fn FED_CRCS_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_CRCS_SHIFT) & FED_CRCS_WIDTH


alias FED_STAT_WIDTH = 0x0000000F
alias FED_STAT_SHIFT = 8
alias FED_STAT_MASK = (FED_STAT_WIDTH << FED_STAT_SHIFT)


@always_inline
fn FED_STAT_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_STAT_SHIFT) & FED_STAT_WIDTH


alias FED_TTSI_WIDTH = 0x0000000F
alias FED_TTSI_SHIFT = 4
alias FED_TTSI_MASK = (FED_TTSI_WIDTH << FED_TTSI_SHIFT)


@always_inline
fn FED_TTSI_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_TTSI_SHIFT) & FED_TTSI_WIDTH


alias FED_MORE_TRAILERS_WIDTH = 0x00000001
alias FED_MORE_TRAILERS_SHIFT = 3
alias FED_MORE_TRAILERS_MASK = (
    FED_MORE_TRAILERS_WIDTH << FED_MORE_TRAILERS_SHIFT
)


@always_inline
fn FED_MORE_TRAILERS_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_MORE_TRAILERS_SHIFT) & FED_MORE_TRAILERS_WIDTH


alias FED_CRC_MODIFIED_WIDTH = 0x00000001
alias FED_CRC_MODIFIED_SHIFT = 2
alias FED_CRC_MODIFIED_MASK = (FED_CRC_MODIFIED_WIDTH << FED_CRC_MODIFIED_SHIFT)


@always_inline
fn FED_CRC_MODIFIED_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_CRC_MODIFIED_SHIFT) & FED_CRC_MODIFIED_WIDTH


alias FED_SLINK_ERROR_WIDTH = 0x00000001
alias FED_SLINK_ERROR_SHIFT = 14
alias FED_SLINK_ERROR_MASK = (FED_SLINK_ERROR_WIDTH << FED_SLINK_ERROR_SHIFT)


@always_inline
fn FED_SLINK_ERROR_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_SLINK_ERROR_SHIFT) & FED_SLINK_ERROR_WIDTH


alias FED_WRONG_FEDID_WIDTH = 0x00000001
alias FED_WRONG_FEDID_SHIFT = 15
alias FED_WRONG_FEDID_MASK = (FED_WRONG_FEDID_WIDTH << FED_WRONG_FEDID_SHIFT)


@always_inline
fn FED_WRONG_FEDID_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_WRONG_FEDID_SHIFT) & FED_WRONG_FEDID_WIDTH


@fieldwise_init
@register_passable("trivial")
struct FEDTrailer(Copyable, Defaultable, Movable, Typeable):
    alias length: UInt32 = sizeof[FedtType]()
    var theTrailer: UnsafePointer[FedtType]

    @always_inline
    fn __init__(out self):
        self.theTrailer = UnsafePointer[FedtType]()

    @always_inline
    fn __init__(out self, trailer: UnsafePointer[UChar]):
        self.theTrailer = trailer.bitcast[FedtType]()

    @always_inline
    fn fragmentLength(self) -> UInt32:
        return FED_EVSZ_EXTRACT(Int(self.theTrailer[].eventsize))

    @always_inline
    fn crc(self) -> UInt16:
        return FED_CRCS_EXTRACT(Int(self.theTrailer[].conscheck))

    @always_inline
    fn evtStatus(self) -> UInt8:
        return FED_STAT_EXTRACT(Int(self.theTrailer[].conscheck))

    @always_inline
    fn ttsBits(self) -> UInt8:
        return FED_TTSI_EXTRACT(Int(self.theTrailer[].conscheck))

    @always_inline
    fn moreTrailers(self) -> Bool:
        return FED_MORE_TRAILERS_EXTRACT(Int(self.theTrailer[].conscheck)) != 0

    @always_inline
    fn crcModified(self) -> Bool:
        return FED_CRC_MODIFIED_EXTRACT(Int(self.theTrailer[].conscheck)) != 0

    @always_inline
    fn slinkError(self) -> Bool:
        return FED_SLINK_ERROR_EXTRACT(Int(self.theTrailer[].conscheck)) != 0

    @always_inline
    fn wrongFedId(self) -> Bool:
        return FED_WRONG_FEDID_EXTRACT(Int(self.theTrailer[].conscheck)) != 0

    @always_inline
    fn check(self) -> Bool:
        return (
            FED_TCTRLID_EXTRACT(Int(self.theTrailer[].eventsize))
            == FED_SLINK_END_MARKER
        )

    @always_inline
    fn conscheck(self) -> UInt32:
        return self.theTrailer[].conscheck

    @staticmethod
    fn set(
        trailer: UnsafePointer[UChar, mut=True],
        var length: UInt32,
        var crc: UInt16,
        var evtStatus: UInt8,
        var ttsBits: UInt8,
        var moreTrailers: Bool = False,
    ):
        var t = trailer.bitcast[FedtType]()

        t[].eventsize = (FED_SLINK_END_MARKER << FED_TCTRLID_SHIFT) | (
            (length << FED_EVSZ_SHIFT) & FED_EVSZ_MASK
        )

        t[].conscheck = (
            ((Int(crc) << FED_CRCS_SHIFT) & FED_CRCS_MASK)
            | ((Int(evtStatus) << FED_STAT_SHIFT) & FED_STAT_MASK)
            | ((Int(ttsBits) << FED_TTSI_SHIFT) & FED_TTSI_MASK)
        )

        if moreTrailers:
            t[].conscheck |= FED_MORE_TRAILERS_WIDTH << FED_MORE_TRAILERS_SHIFT

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "FEDTrailer"
