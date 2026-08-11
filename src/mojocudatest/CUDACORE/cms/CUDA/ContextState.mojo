from SharedStreamPtr import SharedStreamPtr


# Carries CUDA device and stream between acquire() and produce()-style phases.
struct ContextState(Movable):
    var stream_: Optional[SharedStreamPtr]
    var device_: Int

    @always_inline
    fn __init__(out self):
        self.stream_ = None
        self.device_ = -1

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self.stream_ = take.stream_^
        self.device_ = take.device_

    @always_inline
    fn set(mut self, device: Int, var stream: SharedStreamPtr) raises:
        self.throwIfStream()
        self.device_ = device
        self.stream_ = stream^

    @always_inline
    fn device(self) -> Int:
        return self.device_

    @always_inline
    fn streamPtr(self) raises -> SharedStreamPtr:
        self.throwIfNoStream()
        return self.stream_.value()

    @always_inline
    fn releaseStreamPtr(mut self) raises -> SharedStreamPtr:
        self.throwIfNoStream()
        var stream = self.stream_.value()
        self.stream_ = None
        return stream

    @always_inline
    fn throwIfStream(self) raises:
        if self.stream_:
            raise "RuntimeError: Trying to set ContextState, but it already had a valid state"

    @always_inline
    fn throwIfNoStream(self) raises:
        if not self.stream_:
            raise "RuntimeError: Trying to get ContextState, but it did not have a valid state"
