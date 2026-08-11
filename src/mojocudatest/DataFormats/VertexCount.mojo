from MojoBridge.DTypes import Typeable


@fieldwise_init
struct VertexCount(Copyable, Defaultable, Movable, Typeable, TrivialRegisterPassable):
    var _vertcies: UInt32

    @always_inline
    fn __init__(out self):
        self._vertcies = 0

    @always_inline
    fn nVertcies(self) -> UInt32:
        return self._vertcies

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "VertexCount"
