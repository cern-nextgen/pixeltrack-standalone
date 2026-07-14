from math import sqrt
from sys import is_defined

from MojoSerial.plugin_PixelTriplets import CAConstants
from MojoSerial.plugin_PixelTriplets.CirclEq import CircleEq
from MojoSerial.CUDACore.AtomicPairCounter import AtomicPairCounter
from MojoSerial.CUDACore.CUDACompat import CUDACompat
from MojoSerial.CUDACore.VecArray import VecArray
from MojoSerial.CUDADataFormats.PixelTrackHeterogeneous import (
    PixelTrack as pixelTrack,
    TrackQuality as trackQuality,
)
from MojoSerial.CUDADataFormats.TrackingRecHit2DSOAView import (
    TrackingRecHit2DSOAView,
)


@fieldwise_init
struct GPUCACell(Copyable, Defaultable, Movable):
    alias ptrAsInt = UInt64

    alias maxCellsPerHit = CAConstants.maxCellsPerHit()
    alias OuterHitOfCell = CAConstants.OuterHitOfCell
    alias CellNeighbors = CAConstants.CellNeighbors
    alias CellTracks = CAConstants.CellTracks
    alias CellNeighborsVector = CAConstants.CellNeighborsVector
    alias CellTracksVector = CAConstants.CellTracksVector

    alias Hits = TrackingRecHit2DSOAView
    alias hindex_type = Self.Hits.HIndexType

    alias TmpTuple = VecArray[UInt32, "TmpTuple", 6]

    alias HitContainer = pixelTrack.HitContainer
    alias Quality = pixelTrack.Quality
    alias bad = trackQuality.bad

    var theOuterNeighbors: UnsafePointer[Self.CellNeighbors]
    var theTracks: UnsafePointer[Self.CellTracks]

    var theDoubletId: Int32
    var theLayerPairId: Int16
    var theUsed: UInt16  # tbd

    var theInnerZ: Float32
    var theInnerR: Float32
    var theInnerHitId: Self.hindex_type
    var theOuterHitId: Self.hindex_type

    fn __init__(out self):
        self.theOuterNeighbors = UnsafePointer[Self.CellNeighbors]()
        self.theTracks = UnsafePointer[Self.CellTracks]()

        self.theDoubletId = 0
        self.theLayerPairId = 0
        self.theUsed = 0

        self.theInnerZ = 0.0
        self.theInnerR = 0.0
        self.theInnerHitId = 0
        self.theOuterHitId = 0

    fn init(
        mut self,
        mut cellNeighbors: Self.CellNeighborsVector,
        mut cellTracks: Self.CellTracksVector,
        hh: Self.Hits,
        layerPairId: Int32,
        doubletId: Int32,
        innerHitId: Self.hindex_type,
        outerHitId: Self.hindex_type,
    ):
        self.theInnerHitId = innerHitId
        self.theOuterHitId = outerHitId
        self.theDoubletId = doubletId
        self.theLayerPairId = layerPairId.cast[DType.int16]()
        self.theUsed = 0

        var innerIdx = Int(innerHitId)
        self.theInnerZ = hh.zGlobal(innerIdx)
        self.theInnerR = hh.rGlobal(innerIdx)

        # link to default empty
        self.theOuterNeighbors = UnsafePointer(to=cellNeighbors[0])
        self.theTracks = UnsafePointer(to=cellTracks[0])
        debug_assert(self.outerNeighbors().empty())
        debug_assert(self.tracks().empty())

    @always_inline
    fn addOuterNeighbor(
        mut self,
        t: UInt32,
        mut cellNeighbors: Self.CellNeighborsVector,
    ) -> Int32:
        # use smart cache
        if self.outerNeighbors().empty():
            var i = cellNeighbors.extend()  # maybe waisted....
            if i > 0:
                cellNeighbors[i].reset()

                @parameter
                if is_defined["__CUDACC__"]():
                    var zero = UInt64(
                        Int(UnsafePointer(to=cellNeighbors[0]))
                    )
                    _ = CUDACompat.atomicCAS(
                        UnsafePointer(to=self.theOuterNeighbors).bitcast[UInt64](),
                        zero,
                        UInt64(Int(UnsafePointer(to=cellNeighbors[i]))),
                    )
                else:
                    self.theOuterNeighbors = UnsafePointer(
                        to=cellNeighbors[i]
                    )
            else:
                return -1

        return self.outerNeighbors().push_back(t)

    @always_inline
    fn addTrack(
        mut self,
        t: UInt16,
        mut cellTracks: Self.CellTracksVector,
    ) -> Int32:
        if self.tracks().empty():
            var i = cellTracks.extend()  # maybe waisted....
            if i > 0:
                cellTracks[i].reset()

                @parameter
                if is_defined["__CUDACC__"]():
                    var zero = UInt64(Int(UnsafePointer(to=cellTracks[0])))
                    _ = CUDACompat.atomicCAS(
                        UnsafePointer(to=self.theTracks).bitcast[UInt64](),
                        zero,
                        UInt64(Int(UnsafePointer(to=cellTracks[i]))),
                    )
                else:
                    self.theTracks = UnsafePointer(to=cellTracks[i])
            else:
                return -1

        return self.tracks().push_back(t)

    @always_inline
    fn tracks(ref self) -> ref [self.theTracks] Self.CellTracks:
        return self.theTracks[]

    @always_inline
    fn outerNeighbors(ref self) -> ref [self.theOuterNeighbors] Self.CellNeighbors:
        return self.theOuterNeighbors[]

    @always_inline
    fn get_inner_x(self, hh: Self.Hits) -> Float32:
        return hh.xGlobal(Int(self.theInnerHitId))

    @always_inline
    fn get_outer_x(self, hh: Self.Hits) -> Float32:
        return hh.xGlobal(Int(self.theOuterHitId))

    @always_inline
    fn get_inner_y(self, hh: Self.Hits) -> Float32:
        return hh.yGlobal(Int(self.theInnerHitId))

    @always_inline
    fn get_outer_y(self, hh: Self.Hits) -> Float32:
        return hh.yGlobal(Int(self.theOuterHitId))

    @always_inline
    fn get_inner_z(self, hh: Self.Hits) -> Float32:
        return self.theInnerZ

    # { return hh.zGlobal(theInnerHitId); } # { return theInnerZ; }
    @always_inline
    fn get_outer_z(self, hh: Self.Hits) -> Float32:
        return hh.zGlobal(Int(self.theOuterHitId))

    @always_inline
    fn get_inner_r(self, hh: Self.Hits) -> Float32:
        return self.theInnerR

    # { return hh.rGlobal(theInnerHitId); } # { return theInnerR; }
    @always_inline
    fn get_outer_r(self, hh: Self.Hits) -> Float32:
        return hh.rGlobal(Int(self.theOuterHitId))

    @always_inline
    fn get_inner_iphi(self, hh: Self.Hits) -> Int16:
        return hh.iphi(Int(self.theInnerHitId))

    @always_inline
    fn get_outer_iphi(self, hh: Self.Hits) -> Int16:
        return hh.iphi(Int(self.theOuterHitId))

    @always_inline
    fn get_inner_detIndex(self, hh: Self.Hits) -> Float32:
        return Float32(hh.detectorIndex(Int(self.theInnerHitId)))

    @always_inline
    fn get_outer_detIndex(self, hh: Self.Hits) -> Float32:
        return Float32(hh.detectorIndex(Int(self.theOuterHitId)))

    fn get_inner_hit_id(self) -> Self.hindex_type:
        return self.theInnerHitId

    fn get_outer_hit_id(self) -> Self.hindex_type:
        return self.theOuterHitId

    fn print_cell(self):
        print(
            "printing cell: ",
            self.theDoubletId,
            ", on layerPair: ",
            self.theLayerPairId,
            ", innerHitId: ",
            self.theInnerHitId,
            ", outerHitId: ",
            self.theOuterHitId,
        )

    fn check_alignment(
        self,
        hh: Self.Hits,
        otherCell: GPUCACell,
        ptmin: Float32,
        hardCurvCut: Float32,
        CAThetaCutBarrel: Float32,
        CAThetaCutForward: Float32,
        dcaCutInnerTriplet: Float32,
        dcaCutOuterTriplet: Float32,
    ) -> Bool:
        # detIndex of the layerStart for the Phase1 Pixel Detector:
        # [BPX1, BPX2, BPX3, BPX4,  FP1,  FP2,  FP3,  FN1,  FN2,  FN3, LAST_VALID]
        # [   0,   96,  320,  672, 1184, 1296, 1408, 1520, 1632, 1744,       1856]
        alias last_bpix1_detIndex: UInt32 = 96
        alias last_barrel_detIndex: UInt32 = 1184
        var ri = self.get_inner_r(hh)
        var zi = self.get_inner_z(hh)

        var ro = self.get_outer_r(hh)
        var zo = self.get_outer_z(hh)

        var r1 = otherCell.get_inner_r(hh)
        var z1 = otherCell.get_inner_z(hh)
        var isBarrel = otherCell.get_outer_detIndex(hh) < Float32(
            last_barrel_detIndex
        )

        var aligned: Bool = Self.areAlignedRZ(
            r1,
            z1,
            ri,
            zi,
            ro,
            zo,
            ptmin,
            CAThetaCutBarrel if isBarrel else CAThetaCutForward,
        )  # 2.f*thetaCut); # FIXME tune cuts

        return aligned and self.dcaCut(
            hh,
            otherCell,
            dcaCutInnerTriplet if otherCell.get_inner_detIndex(hh)
            < Float32(last_bpix1_detIndex) else dcaCutOuterTriplet,
            hardCurvCut,
        )  # FIXME tune cuts

    @staticmethod
    fn areAlignedRZ(
        r1: Float32,
        z1: Float32,
        ri: Float32,
        zi: Float32,
        ro: Float32,
        zo: Float32,
        ptmin: Float32,
        thetaCut: Float32,
    ) -> Bool:
        var radius_diff = abs(r1 - ro)
        var distance_13_squared = radius_diff * radius_diff + (z1 - zo) * (
            z1 - zo
        )

        var pMin = ptmin * sqrt(
            distance_13_squared
        )  # this needs to be divided by radius_diff later

        var tan_12_13_half_mul_distance_13_squared = abs(
            z1 * (ri - ro) + zi * (ro - r1) + zo * (r1 - ri)
        )
        return (
            tan_12_13_half_mul_distance_13_squared * pMin
            <= thetaCut * distance_13_squared * radius_diff
        )

    fn dcaCut(
        self,
        hh: Self.Hits,
        otherCell: GPUCACell,
        region_origin_radius_plus_tolerance: Float32,
        maxCurv: Float32,
    ) -> Bool:
        var x1 = otherCell.get_inner_x(hh)
        var y1 = otherCell.get_inner_y(hh)

        var x2 = self.get_inner_x(hh)
        var y2 = self.get_inner_y(hh)

        var x3 = self.get_outer_x(hh)
        var y3 = self.get_outer_y(hh)

        var eq = CircleEq[DType.float32](x1, y1, x2, y2, x3, y3)

        if eq.curvature() > maxCurv:
            return False

        return abs(eq.dca0()) < region_origin_radius_plus_tolerance * abs(
            eq.curvature()
        )

    @staticmethod
    fn dcaCutH(
        x1: Float32,
        y1: Float32,
        x2: Float32,
        y2: Float32,
        x3: Float32,
        y3: Float32,
        region_origin_radius_plus_tolerance: Float32,
        maxCurv: Float32,
    ) -> Bool:
        var eq = CircleEq[DType.float32](x1, y1, x2, y2, x3, y3)

        if eq.curvature() > maxCurv:
            return False

        return abs(eq.dca0()) < region_origin_radius_plus_tolerance * abs(
            eq.curvature()
        )

    fn hole0(self, hh: Self.Hits, innerCell: GPUCACell) -> Bool:
        alias max_ladder_bpx0: UInt32 = 12
        alias first_ladder_bpx0: UInt32 = 0
        alias module_length: Float32 = 6.7
        alias module_tolerance: Float32 = 0.4  # projection to cylinder is inaccurate on BPIX1
        alias max_ushort: Int = 65535

        var p: Int = Int(innerCell.get_inner_iphi(hh))
        if p < 0:
            p += max_ushort
        p = (Int(max_ladder_bpx0) * p) // max_ushort
        p = p % Int(max_ladder_bpx0)
        var il = Int(first_ladder_bpx0) + p
        ref avg = hh.averageGeometry()
        var r0 = avg.ladderR[il]
        var ri = innerCell.get_inner_r(hh)
        var zi = innerCell.get_inner_z(hh)
        var ro = self.get_outer_r(hh)
        var zo = self.get_outer_z(hh)
        var z0 = zi + (r0 - ri) * (zo - zi) / (ro - ri)
        var z_in_ladder = abs(z0 - avg.ladderZ[il])
        var z_in_module = z_in_ladder - module_length * Float32(
            Int(z_in_ladder / module_length)
        )
        var gap = z_in_module < module_tolerance or z_in_module > (
            module_length - module_tolerance
        )
        return gap

    @always_inline
    fn hole4(self, hh: Self.Hits, innerCell: GPUCACell) -> Bool:
        alias max_ladder_bpx4: UInt32 = 64
        alias first_ladder_bpx4: UInt32 = 84
        alias module_length: Float32 = 6.7
        alias module_tolerance: Float32 = 0.2
        alias max_ushort: Int = 65535

        var p: Int = Int(self.get_outer_iphi(hh))
        if p < 0:
            p += max_ushort
        p = (Int(max_ladder_bpx4) * p) // max_ushort
        p = p % Int(max_ladder_bpx4)
        var il = Int(first_ladder_bpx4) + p
        ref avg = hh.averageGeometry()
        var r4 = avg.ladderR[il]
        var ri = innerCell.get_inner_r(hh)
        var zi = innerCell.get_inner_z(hh)
        var ro = self.get_outer_r(hh)
        var zo = self.get_outer_z(hh)
        var z4 = zo + (r4 - ro) * (zo - zi) / (ro - ri)
        var z_in_ladder = abs(z4 - avg.ladderZ[il])
        var z_in_module = z_in_ladder - module_length * Float32(
            Int(z_in_ladder / module_length)
        )
        var gap = z_in_module < module_tolerance or z_in_module > (
            module_length - module_tolerance
        )
        var holeP = z4 > avg.ladderMaxZ[il] and z4 < avg.endCapZ[0]
        var holeN = z4 < avg.ladderMinZ[il] and z4 > avg.endCapZ[1]
        return gap or holeP or holeN

    # trying to free the track building process from hardcoded layers, leaving
    # the visit of the graph based on the neighborhood connections between cells.
    fn find_ntuplets[
        DEPTH: Int
    ](
        self,
        hh: Self.Hits,
        cells: UnsafePointer[GPUCACell],
        mut cellTracks: Self.CellTracksVector,
        mut foundNtuplets: Self.HitContainer,
        mut apc: AtomicPairCounter,
        quality: UnsafePointer[Self.Quality],
        mut tmpNtuplet: Self.TmpTuple,
        minHitsPerNtuplet: UInt32,
        startAt0: Bool,
    ):
        # the building process for a track ends if:
        # it has no right neighbor
        # it has no compatible neighbor
        # the ntuplets is then saved if the number of hits it contains is greater
        # than a threshold

        @parameter
        if DEPTH == 0:
            print("ERROR: GPUCACell::find_ntuplets reached full depth!")
            debug_assert(False)
            return

        _ = tmpNtuplet.push_back_unsafe(self.theDoubletId.cast[DType.uint32]())
        debug_assert(len(tmpNtuplet) <= 4)

        var last = True
        var nNeighbors = len(self.outerNeighbors())
        var j: Int = 0
        while j < nNeighbors:
            var otherCell = self.outerNeighbors()[Int32(j)]
            var otherIdx = Int(otherCell)
            if (cells + otherIdx)[].theDoubletId < 0:
                # killed by earlyFishbone
                j += 1
                continue
            last = False
            (cells + otherIdx)[].find_ntuplets[DEPTH - 1](
                hh,
                cells,
                cellTracks,
                foundNtuplets,
                apc,
                quality,
                tmpNtuplet,
                minHitsPerNtuplet,
                startAt0,
            )
            j += 1

        if last:  # if long enough save...
            if UInt32(len(tmpNtuplet)) >= minHitsPerNtuplet - 1:
                var accept = True

                @parameter
                if is_defined["ONLY_TRIPLETS_IN_HOLE"]():
                    # triplets accepted only pointing to the hole
                    var firstCell = tmpNtuplet[0]
                    var inner = (cells + Int(firstCell))[]
                    accept = (
                        len(tmpNtuplet) >= 3
                        or (startAt0 and self.hole4(hh, inner))
                        or ((not startAt0) and self.hole0(hh, inner))
                    )
                if accept:
                    var hits = InlineArray[Self.hindex_type, 6](fill=0)
                    var nh: UInt32 = 0
                    var tupleSize = len(tmpNtuplet)
                    var i: Int = 0
                    while i < tupleSize:
                        var cellIdx = tmpNtuplet[Int32(i)]
                        hits[Int(nh)] = (cells + Int(cellIdx))[].theInnerHitId
                        nh += 1
                        i += 1
                    hits[Int(nh)] = self.theOuterHitId
                    var it = foundNtuplets.bulkFill(
                        apc,
                        hits.unsafe_ptr(),
                        UInt32(tupleSize + 1),
                    )
                    if it >= 0:  # if negative is overflow....
                        i = 0
                        while i < tupleSize:
                            var cellIdx = tmpNtuplet[Int32(i)]
                            _ = (cells + Int(cellIdx))[].addTrack(
                                UInt16(it), cellTracks
                            )
                            i += 1
                        quality[Int(it)] = Self.bad  # initialize to bad

        _ = tmpNtuplet.pop_back()
        debug_assert(len(tmpNtuplet) < 4)

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "GPUCACell"
