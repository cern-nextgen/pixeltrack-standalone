from sys import sizeof

from MojoBridge.DTypes import Typeable, UChar


@fieldwise_init
@register_passable("trivial")
struct FedhStruct(Copyable, Defaultable, Movable, Typeable):
    var sourceid: UInt32
    var eventid: UInt32

    @always_inline
    fn __init__(out self):
        self.sourceid = 0
        self.eventid = 0

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "FedhStruct"


alias FedhType = FedhStruct

alias FED_SLINK_START_MARKER = 0x5

alias FED_HCTRLID_WIDTH = 0x0000000F
alias FED_HCTRLID_SHIFT = 28
alias FED_HCTRLID_MASK = (FED_HCTRLID_WIDTH << FED_HCTRLID_SHIFT)


@always_inline
fn FED_HCTRLID_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_HCTRLID_SHIFT) & FED_HCTRLID_WIDTH


alias FED_EVTY_WIDTH = 0x0000000F
alias FED_EVTY_SHIFT = 24
alias FED_EVTY_MASK = (FED_EVTY_WIDTH << FED_EVTY_SHIFT)


@always_inline
fn FED_EVTY_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_EVTY_SHIFT) & FED_EVTY_WIDTH


alias FED_LVL1_WIDTH = 0x00FFFFFF
alias FED_LVL1_SHIFT = 0
alias FED_LVL1_MASK = (FED_LVL1_WIDTH << FED_LVL1_SHIFT)


@always_inline
fn FED_LVL1_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_LVL1_SHIFT) & FED_LVL1_WIDTH


alias FED_BXID_WIDTH = 0x00000FFF
alias FED_BXID_SHIFT = 20
alias FED_BXID_MASK = (FED_BXID_WIDTH << FED_BXID_SHIFT)


@always_inline
fn FED_BXID_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_BXID_SHIFT) & FED_BXID_WIDTH


alias FED_SOID_WIDTH = 0x00000FFF
alias FED_SOID_SHIFT = 8
alias FED_SOID_MASK = (FED_SOID_WIDTH << FED_SOID_SHIFT)


@always_inline
fn FED_SOID_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_SOID_SHIFT) & FED_SOID_WIDTH


alias FED_VERSION_WIDTH = 0x0000000F
alias FED_VERSION_SHIFT = 4
alias FED_VERSION_MASK = (FED_VERSION_WIDTH << FED_VERSION_SHIFT)


@always_inline
fn FED_VERSION_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_VERSION_SHIFT) & FED_VERSION_WIDTH


alias FED_MORE_HEADERS_WIDTH = 0x00000001
alias FED_MORE_HEADERS_SHIFT = 3
alias FED_MORE_HEADERS_MASK = (FED_MORE_HEADERS_WIDTH << FED_MORE_HEADERS_SHIFT)


@always_inline
fn FED_MORE_HEADERS_EXTRACT(a: Int) -> Int:
    return ((a) >> FED_MORE_HEADERS_SHIFT) & FED_MORE_HEADERS_WIDTH


@fieldwise_init
@register_passable("trivial")
struct FEDHeader(Copyable, Defaultable, Movable, Typeable):
    alias length: UInt32 = sizeof[FedhType]()
    var theHeader: UnsafePointer[FedhType]

    @always_inline
    fn __init__(out self):
        self.theHeader = UnsafePointer[FedhType]()

    @always_inline
    fn __init__(out self, header: UnsafePointer[UChar]):
        self.theHeader = header.bitcast[FedhType]()

    @always_inline
    fn triggerType(self) -> UInt8:
        return FED_EVTY_EXTRACT(Int(self.theHeader[].eventid))

    @always_inline
    fn lvl1ID(self) -> UInt32:
        return FED_LVL1_EXTRACT(Int(self.theHeader[].eventid))

    @always_inline
    fn bxID(self) -> UInt16:
        return FED_BXID_EXTRACT(Int(self.theHeader[].sourceid))

    @always_inline
    fn sourceID(self) -> UInt16:
        return FED_SOID_EXTRACT(Int(self.theHeader[].sourceid))

    @always_inline
    fn version(self) -> UInt8:
        return FED_VERSION_EXTRACT(Int(self.theHeader[].sourceid))

    @always_inline
    fn moreHeaders(self) -> Bool:
        return FED_MORE_HEADERS_EXTRACT(Int(self.theHeader[].sourceid)) != 0

    @always_inline
    fn check(self) -> Bool:
        return (
            FED_HCTRLID_EXTRACT(Int(self.theHeader[].eventid))
            == FED_SLINK_START_MARKER
        )

    @staticmethod
    fn set(
        header: UnsafePointer[UChar, mut=True],
        triggerType: UInt8,
        lvl1ID: UInt32,
        bxID: UInt16,
        sourceID: UInt16,
        version: UInt8 = 0,
        moreHeaders: Bool = False,
    ):
        var h = header.bitcast[FedhType]()
        h[].eventid = (
            (FED_SLINK_START_MARKER << FED_HCTRLID_SHIFT)
            | ((Int(triggerType) << FED_EVTY_SHIFT) & FED_EVTY_MASK)
            | ((lvl1ID << FED_LVL1_SHIFT) & FED_LVL1_MASK)
        )
        h[].sourceid = (
            ((Int(bxID) << FED_BXID_SHIFT) & FED_BXID_MASK)
            | ((Int(sourceID) << FED_SOID_SHIFT) & FED_SOID_MASK)
            | ((Int(version) << FED_VERSION_SHIFT) & FED_VERSION_MASK)
        )
        if moreHeaders:
            h[].sourceid |= FED_MORE_HEADERS_WIDTH << FED_MORE_HEADERS_SHIFT

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "FEDHeader"
