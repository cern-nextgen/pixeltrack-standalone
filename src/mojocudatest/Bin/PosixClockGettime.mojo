from std.ffi import external_call, c_long, c_int

alias TimeType = c_int
alias Long = c_long
alias ClockIdType = c_int

alias CLOCK_REALTIME: ClockIdType = 0
alias CLOCK_MONOTONIC: ClockIdType = 1
alias CLOCK_PROCESS_CPUTIME_ID: ClockIdType = 2
alias CLOCK_THREAD_CPUTIME_ID: ClockIdType = 3


@always_inline
fn is_steady[CLOCK: ClockIdType]() -> Bool:
    @parameter
    if CLOCK == CLOCK_REALTIME:
        return False
    elif CLOCK == CLOCK_MONOTONIC:
        return False
    elif CLOCK == CLOCK_PROCESS_CPUTIME_ID:
        return False
    elif CLOCK == CLOCK_THREAD_CPUTIME_ID:
        return False
    return False


@fieldwise_init
struct TimeSpec(Copyable, Defaultable, Movable, TrivialRegisterPassable):
    var tv_sec: TimeType
    var tv_nsec: c_long

    @always_inline
    fn __init__(out self):
        self.tv_sec = 0
        self.tv_nsec = 0


struct PosixClockGettime[CLOCK: ClockIdType]:
    alias rep = UInt
    alias period = 10**9

    alias is_steady = is_steady[CLOCK]()

    @staticmethod
    fn now() -> Self.rep:
        """Returns clock_gettime in nsec."""
        var t = TimeSpec()
        debug_assert(
            external_call[
                "clock_gettime", c_int, ClockIdType, UnsafePointer[TimeSpec, MutAnyOrigin]
            ](Self.CLOCK, UnsafePointer(to=t))
            == 0
        )
        return UInt(c_long(t.tv_sec) * Self.period + t.tv_nsec)
