from MojoSerial.CUDADataFormats.PixelTrackHeterogeneous import (
    PixelTrack as pixelTrack,
)
from MojoSerial.CUDADataFormats.ZVertexHeterogeneous import ZVertexHeterogeneous
from MojoSerial.CUDADataFormats.ZVertexSoA import ZVertexSoA
from MojoSerial.MojoBridge.DTypes import Float, Typeable

alias ZVertices = ZVertexSoA
alias TkSoA = pixelTrack.TrackSoA


# workspace used in the vertex reco algos
@fieldwise_init
struct WorkSpace(Copyable, Defaultable, Movable, Typeable):
    alias MAXTRACKS = ZVertexSoA.MAXTRACKS
    alias MAXVTX = ZVertexSoA.MAXVTX

    var ntrks: UInt32  # number of "selected tracks"
    var itrk: InlineArray[UInt16, UInt(Self.MAXTRACKS)]  # index of original track
    var zt: InlineArray[Float, UInt(Self.MAXTRACKS)]  # input track z at bs
    var ezt2: InlineArray[Float, UInt(Self.MAXTRACKS)]  # input error^2 on the above
    var ptt2: InlineArray[Float, UInt(Self.MAXTRACKS)]  # input pt^2 on the above
    var izt: InlineArray[
        UInt8, UInt(Self.MAXTRACKS)
    ]  # interized z-position of input tracks
    var iv: InlineArray[
        Int32, UInt(Self.MAXTRACKS)
    ]  # vertex index for each associated track

    var nvIntermediate: UInt32  # the number of vertices after splitting pruning etc.

    @always_inline
    fn __init__(out self):
        self.ntrks = 0
        self.itrk = InlineArray[UInt16, UInt(Self.MAXTRACKS)](fill=0)
        self.zt = InlineArray[Float, UInt(Self.MAXTRACKS)](fill=0.0)
        self.ezt2 = InlineArray[Float, UInt(Self.MAXTRACKS)](fill=0.0)
        self.ptt2 = InlineArray[Float, UInt(Self.MAXTRACKS)](fill=0.0)
        self.izt = InlineArray[UInt8, UInt(Self.MAXTRACKS)](fill=0)
        self.iv = InlineArray[Int32, UInt(Self.MAXTRACKS)](fill=0)
        self.nvIntermediate = 0

    @always_inline
    fn init(mut self):
        self.ntrks = 0
        self.nvIntermediate = 0

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "WorkSpace"


@always_inline
fn init(pdata: UnsafePointer[ZVertexSoA], pws: UnsafePointer[WorkSpace]):
    pdata[].init()
    pws[].init()


struct Producer(Typeable):
    alias ZVertices = ZVertexSoA
    alias WorkSpace = WorkSpace
    alias TkSoA = pixelTrack.TrackSoA

    var oneKernel_: Bool
    var useDensity_: Bool
    var useDBSCAN_: Bool
    var useIterative_: Bool

    var minT: Int32  # min number of neighbours to be "core"
    var eps: Float  # max absolute distance to cluster
    var errmax: Float  # max error to be "seed"
    var chi2max: Float  # max normalized distance to cluster

    @always_inline
    fn __init__(
        out self,
        oneKernel: Bool,
        useDensity: Bool,
        useDBSCAN: Bool,
        useIterative: Bool,
        iminT: Int32,  # min number of neighbours to be "core"
        ieps: Float,  # max absolute distance to cluster
        ierrmax: Float,  # max error to be "seed"
        ichi2max: Float,  # max normalized distance to cluster
    ):
        self.oneKernel_ = oneKernel and not (useDBSCAN or useIterative)
        self.useDensity_ = useDensity
        self.useDBSCAN_ = useDBSCAN
        self.useIterative_ = useIterative
        self.minT = iminT
        self.eps = ieps
        self.errmax = ierrmax
        self.chi2max = ichi2max

    fn make(
        self, tksoa: UnsafePointer[Self.TkSoA], ptMin: Float
    ) raises -> ZVertexHeterogeneous:
        # TODO: port gpuVertexFinderImpl.h (loadTracks, clusterTracksByDensity/
        # DBSCAN/Iterative, fitVertices, splitVertices, sortByPt2) and implement
        # this method against it.
        raise "NotImplementedError: Producer.make is not yet ported"

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "Producer"
