from memory import OwnedPointer

from MojoSerial.CUDACore.CUDACompat import CUDACompat
from MojoSerial.CUDADataFormats.PixelTrackHeterogeneous import (
    PixelTrack as pixelTrack,
    TrackQuality,
)
from MojoSerial.CUDADataFormats.ZVertexHeterogeneous import ZVertexHeterogeneous
from MojoSerial.CUDADataFormats.ZVertexSoA import ZVertexSoA
from MojoSerial.MojoBridge.DTypes import Float, Typeable
from MojoSerial.plugin_PixelVertexFinding.gpuClusterTracksByDensity import (
    clusterTracksByDensity,
)
from MojoSerial.plugin_PixelVertexFinding.gpuFitVertices import fitVertices
from MojoSerial.plugin_PixelVertexFinding.gpuSortByPt2 import sortByPt2
from MojoSerial.plugin_PixelVertexFinding.gpuSplitVertices import splitVertices

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


@always_inline
fn loadTracks(
    ptracks: UnsafePointer[TkSoA],
    soa: UnsafePointer[ZVertexSoA],
    pws: UnsafePointer[WorkSpace],
    ptMin: Float,
):
    debug_assert(Bool(ptracks))
    debug_assert(Bool(soa))
    ref tracks = ptracks[]
    ref fit = tracks.stateAtBS
    var quality = tracks.qualityData()

    for idx in range(TkSoA.stride()):
        var nHits = tracks.nHits(idx)
        if nHits == 0:
            break  # this is a guard: maybe we need to move to nTracks...

        # initialize soa...
        soa[].idv[Int(idx)] = -1

        if nHits < 4:
            continue  # no triplets
        if quality[Int(idx)] != TrackQuality.loose:
            continue

        var pt = tracks.pt[Int(idx)]

        if pt < ptMin:
            continue

        ref data = pws[]
        var it = CUDACompat.atomicAdd(UnsafePointer(to=data.ntrks), UInt32(1))
        data.itrk[Int(it)] = UInt16(idx)
        data.zt[Int(it)] = tracks.zip(idx)
        data.ezt2[Int(it)] = rebind[Scalar[DType.float32]](
            fit.covariance[idx][14, 0]
        )
        data.ptt2[Int(it)] = pt * pt


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
        var vertices: ZVertexHeterogeneous = ZVertexHeterogeneous(ZVertexSoA())
        debug_assert(Bool(tksoa))
        var soa = vertices.unsafe_ptr()
        debug_assert(Bool(soa))

        var ws_d = OwnedPointer(WorkSpace())

        init(soa, ws_d.unsafe_ptr())
        loadTracks(tksoa, soa, ws_d.unsafe_ptr(), ptMin)

        if self.useDensity_:
            clusterTracksByDensity(
                soa, ws_d.unsafe_ptr(), self.minT, self.eps, self.errmax, self.chi2max
            )
        elif self.useDBSCAN_:
            raise "NotImplementedError: clusterTracksDBSCAN is not yet ported"
        elif self.useIterative_:
            raise "NotImplementedError: clusterTracksIterative is not yet ported"

        fitVertices(soa, ws_d.unsafe_ptr(), 50.0)
        # one block per vertex!
        splitVertices(soa, ws_d.unsafe_ptr(), 9.0)
        fitVertices(soa, ws_d.unsafe_ptr(), 5000.0)
        sortByPt2(soa, ws_d.unsafe_ptr())

        return vertices^

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "Producer"
