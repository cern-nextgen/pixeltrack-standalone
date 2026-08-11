from MojoBridge.OrderedMap import OrderedMap


@fieldwise_init
struct TotalBytes(Copyable, ImplicitlyCopyable, Defaultable, Movable):
    var free: UInt
    var live: UInt
    var liveRequested: UInt

    @always_inline
    fn __init__(out self):
        self.free = 0
        self.live = 0
        self.liveRequested = 0


# C++: using GpuCachedBytes = std::map<int, TotalBytes>;
# We use an ordered map (RB-tree based) for deterministic key ordering.
alias GpuCachedBytes = OrderedMap[Int, TotalBytes]
