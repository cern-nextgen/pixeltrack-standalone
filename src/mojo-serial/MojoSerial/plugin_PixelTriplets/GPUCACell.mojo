import math
from sys import is_defined

import CAConstants
from CirclEq import CircleEq
from MojoSerial.CUDACore.AtomicPairCounter import AtomicPairCounter
from MojoSerial.CUDACore.CUDACompat import CUDACompat
from MojoSerial.CUDACore.SimpleVector import SimpleVector
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
    alias hindex_type = Hits.HIndexType

    alias TmpTuple = VecArray[UInt32, "TmpTuple", 6]

    alias HitContainer = pixelTrack.HitContainer
    alias Quality = trackQuality.Quality
    alias bad = trackQuality.bad

    var theOuterNeighbors: UnsafePointer[CellNeighbors]
    var theTracks: UnsafePointer[CellTracks]

    var theDoubletId: Int32
    var theLayerPairId: Int16
    var theUsed: UInt16

    var theInnerZ: Float32
    var theInnerR: Float32
    var theInnerHitId: hindex_type
    var theOuterHitId: hindex_type

    fn __init__(out self):
        self.theOuterNeighbors = UnsafePointer[CellNeighbors]()
        self.theTracks = UnsafePointer[CellTracks]()

        self.theDoubletId = 0
        self.theLayerPairId = 0
        self.theUsed = 0

        self.theInnerZ = 0.0
        self.theInnerR = 0.0
        self.theInnerHitId = 0
        self.theOuterHitId = 0

    @always_inline
    fn outerNeighbors(ref self) -> ref [self.theOuterNeighbors] CellNeighbors:
        return self.theOuterNeighbors[]

    @always_inline
    fn outerNeighbors(self: mut Self) -> mut CellNeighbors:
        return self.theOuterNeighbors[]

    @always_inline
    fn tracks(ref self) -> ref [self.theTracks] CellTracks:
        return self.theTracks[]

    @always_inline
    fn tracks(self: mut Self) -> mut CellTracks:
        return self.theTracks[]

    fn get_inner_hit_id(self) -> hindex_type:
        return self.theInnerHitId

    fn get_outer_hit_id(self) -> hindex_type:
        return self.theOuterHitId

    @always_inline
    fn get_inner_x(self: read Self,hh: read Hits) -> Float32:
        return hh.xGlobal(self.theInnerHitId.cast[Int]())

    @always_inline
    fn get_outer_x(self: read Self,hh: read Hits) -> Float32:
        return hh.xGlobal(self.theOuterHitId.cast[Int]())

    @always_inline
    fn get_inner_y(self: read Self,hh: read Hits) -> Float32:
        return hh.yGlobal(self.theInnerHitId.cast[Int]())

    @always_inline
    fn get_outer_y(self: read Self,hh: read Hits) -> Float32:
        return hh.yGlobal(self.theOuterHitId.cast[Int]())

    @always_inline
    fn get_inner_z(self: read Self,hh: read Hits) -> Float32:
        return self.theInnerZ

    @always_inline
    fn get_outer_z(self: read Self,hh: read Hits) -> Float32:
        return hh.zGlobal(self.theOuterHitId.cast[Int]())

    @always_inline
    fn get_inner_r(self: read Self,hh: read Hits) -> Float32:
        return self.theInnerR

    @always_inline
    fn get_outer_r(self: read Self,hh: read Hits) -> Float32:
        return hh.rGlobal(self.theOuterHitId.cast[Int]())

    @always_inline
    fn get_inner_iphi(self: read Self,hh: read Hits):
        return hh.iphi(self.theInnerHitId.cast[Int]())

    @always_inline
    fn get_outer_iphi(self: read Self,hh: read Hits):
        return hh.iphi(self.theOuterHitId.cast[Int]())

    @always_inline
    fn get_inner_detIndex(self: read Self,hh: read Hits) -> Float32:
        return hh.detectorIndex(self.theInnerHitId.cast[Int]())

    @always_inline
    fn get_outer_detIndex(self: read Self,hh: read Hits) -> Float32:
        return hh.detectorIndex(self.theOuterHitId.cast[Int]())

    fn init(
        mut self,
        mut cellNeighbors: CellNeighborsVector,
        mut cellTracks: CellTracksVector,
        read hh: Hits,
        layerPairId: Int32,
        doubletId: Int32,
        innerHitId: hindex_type,
        outerHitId: hindex_type,
    ):
        self.theInnerHitId = innerHitId
        self.theOuterHitId = outerHitId
        self.theDoubletId = doubletId
        self.theLayerPairId = layerPairId.cast[Int16]()
        self.theUsed = 0

        let innerIdx = innerHitId.cast[Int]()
        self.theInnerZ = hh.zGlobal(innerIdx)
        self.theInnerR = hh.rGlobal(innerIdx)

        self.theOuterNeighbors = UnsafePointer(to=self.cellNeighbors[0])
        self.theTracks = UnsafePointer(to=self.cellTracks[0])
        assert self.outerNeighbors().empty()
        assert self.tracks().empty()

    fn __moveinit__(out self, var other: Self):
        self.theDoubletId = other.theDoubletId
        self.theLayerPairId = other.theLayerPairId
        self.theUsed = other.theUsed

        self.theInnerZ = other.theInnerZ
        self.theInnerR = other.theInnerR
        self.theInnerHitId = other.theInnerHitId
        self.theOuterHitId = other.theOuterHitId

        self.theOuterNeighbors = UnsafePointer(to=self.cellNeighbors[0])
        self.theTracks = UnsafePointer(to=self.cellTracks[0])

    @always_inline
    fn addOuterNeighbor(
        mut self,
        t: UInt32,
        mut cellNeighbors: CellNeighborsVector,
    ) -> Int32:
        if self.outerNeighbors().empty():
            var i = cellNeighbors.extend()
            if i > 0:
                cellNeighbors[i].reset()
                if is_defined["__CUDACC__"]():
                    var zero = ptrAsInt(UnsafePointer(to=(cellNeighbors[0])).__init__())
                    _ = CUDACompat.atomicCAS(
                        UnsafePointer(to=self.theOuterNeighbors).bitcast[ptrAsInt](),
                        zero,
                        ptrAsInt((UnsafePointer(to=cellNeighbors[i])).__init__()),
                    )
                else:
                    self.theOuterNeighbors = UnsafePointer(to=cellNeighbors[i])
            else:
                return -1

        return self.outerNeighbors().push_back(t)

    @always_inline
    fn addTrack(
        mut self,
        t: UInt16,
        mut cellTracks: CellTracksVector,
    ) -> Int32:
        if self.tracks().empty():
            var i = cellTracks.extend()
            if i > 0:
                cellTracks[i].reset()
                if is_defined["__CUDACC__"]():
                    var zero = ptrAsInt(UnsafePointer(to=(cellTracks[0])).__init__())
                    _ = CUDACompat.atomicCAS(
                        UnsafePointer(to=self.theTracks).bitcast[ptrAsInt](),
                        zero,
                        ptrAsInt((UnsafePointer(to=cellTracks[i])).__init__()),
                    )
                else:
                    self.theTracks = UnsafePointer(to=cellTracks[i])
            else:
                return -1

        return self.tracks().push_back(t)


    fn print_cell(self):
        print(
            "printing cell: {}, on layerPair: {}, innerHitId: {}, outerHitId: {}\n"
                .format(
                    self.theDoubletId,
                    self.theLayerPairId,
                    self.theInnerHitId,
                    self.theOuterHitId
                )
        )

    fn check_alignment(self , hh : Hits ,
                        otherCell : GPUCACell , 
                        ptmin: Float32,
                        hardCurvCut: Float32,
                        CAThetaCutBarrel: Float32,
                        CAThetaCutForward: Float32,
                        dcaCutInnerTriplet: Float32,
                        dcaCutOuterTriplet: Float32) -> Bool :
        comptime last_bpix1_detIndex : UInt32 = 96
        comptime last_barrel_detIndex :UInt32 = 1184
        var ri =  get_inner_r(hh)
        var zi = get_inner_z(hh)

        var ro = get_outer_r(hh)
        var zo = get_outer_z(hh)

        var r1 = otherCell.get_inner_r(hh)
        var z1 = otherCell.get_inner_z(hh)
        var isBarrel = otherCell.get_outer_detIndex(hh) < last_barrel_detIndex

        let aligned : Bool = areAlignedRZ(r1 ,
                                    z1 , 
                                    ri ,
                                    zi ,
                                    ro ,
                                    zo ,
                                    ptmin ,
                                    CAThetaCutBarrel if isBarrel else CAThetaCutForward)

        return aligned and dcaCut(
                    hh,
                    otherCell,
                    dcaCutInnerTriplet if otherCell.get_inner_detIndex(hh) < last_bpix1_detIndex
                    else dcaCutOuterTriplet,
                    hardCurvCut
                )

    fn areAlignedRZ(
        r1: Float32,
        z1: Float32,
        ri: Float32,
        zi: Float32,
        ro: Float32,
        zo: Float32,
        ptmin: Float32,
        thetaCut: Float32
    ) -> Bool:
        # abs and sqrt come from builtin math and math.sqrt [[Builtin math](<https://docs.modular.com/mojo/std/builtin/math/>); [sqrt](<https://docs.modular.com/mojo/std/math/math/sqrt/>)]
        let radius_diff: Float32 = abs(r1 - ro)
        let dz_13: Float32 = z1 - zo
        let distance_13_squared: Float32 = radius_diff * radius_diff + dz_13 * dz_13

        let pMin: Float32 = ptmin * math.sqrt(distance_13_squared)

        let tan_12_13_half_mul_distance_13_squared: Float32 = abs(
            z1 * (ri - ro) +
            zi * (ro - r1) +
            zo * (r1 - ri)
        )

        return tan_12_13_half_mul_distance_13_squared * pMin \
            <= thetaCut * distance_13_squared * radius_diff

    fn dcaCut(
        self,
        hh: Hits,
        otherCell: GPUCACell,
        region_origin_radius_plus_tolerance: Float32,
        maxCurv: Float32
    ) -> Bool:
        let x1 = otherCell.get_inner_x(hh)
        let y1 = otherCell.get_inner_y(hh)

        let x2 = self.get_inner_x(hh)
        let y2 = self.get_inner_y(hh)

        let x3 = self.get_outer_x(hh)
        let y3 = self.get_outer_y(hh)

        let eq = CircleEq[Float32](x1, y1, x2, y2, x3, y3)

        if eq.curvature() > maxCurv:
            return False

        return abs(eq.dca0()) < region_origin_radius_plus_tolerance * abs(eq.curvature())


    fn dcaCutH(
        x1: Float32,
        y1: Float32,
        x2: Float32,
        y2: Float32,
        x3: Float32,
        y3: Float32,
        region_origin_radius_plus_tolerance: Float32,
        maxCurv: Float32
    ) -> Bool:

        var eq = CircleEq[Float32](x1, y1, x2, y2, x3, y3)

        if eq.curvature() > maxCurv:
            return False

        return abs(eq.dca0()) < region_origin_radius_plus_tolerance * abs(eq.curvature())

    fn hole0(
        self,
        hh: Hits,
        innerCell: GPUCACell
    ) -> Bool:
        comptime max_ladder_bpx0: UInt32 = 12
        comptime first_ladder_bpx0: UInt32 = 0
        comptime module_length: Float32 = 6.7
        comptime module_tolerance: Float32 = 0.4
        comptime max_ushort: Int = 65535

        var p : Int = innerCell.get_inner_iphi(hh).cast[Int]()
        if p < 0:
            p += max_ushort
        p = (max_ladder_bpx0 * p) / max_ushort
        p = p % max_ladder_bpx0
        let il = first_ladder_bpx0 + p
        let avg = hh.averageGeometry()
        let r0 = avg.ladderR[il]
        let ri = innerCell.get_inner_r(hh)
        let zi = innerCell.get_inner_z(hh)
        let ro = self.get_outer_r(hh)
        let zo = self.get_outer_z(hh)
        let z0 = zi + (r0 - ri) * (zo - zi) / (ro - ri)
        let z_in_ladder = abs(z0 - avg.ladderZ[il])
        let z_in_module = z_in_ladder - module_length * Float32(
            Int(z_in_ladder / module_length)
        )
        let gap = z_in_module < module_tolerance or \
            z_in_module > (module_length - module_tolerance)
        return gap

    @always_inline
    fn hole4(
        self,
        hh: Hits,
        innerCell: GPUCACell
    ) -> Bool:
        comptime max_ladder_bpx4: UInt32 = 64
        comptime first_ladder_bpx4: UInt32 = 84
        comptime module_length: Float32 = 6.7
        comptime module_tolerance: Float32 = 0.2
        comptime max_ushort: Int = 65535

        var p : Int = self.get_outer_iphi(hh).cast[Int]()
        if p < 0:
            p += max_ushort
        p = (max_ladder_bpx4 * p) / max_ushort
        p = p % max_ladder_bpx4
        let il = first_ladder_bpx4 + p
        let avg = hh.averageGeometry()
        let r4 = avg.ladderR[il]
        let ri = innerCell.get_inner_r(hh)
        let zi = innerCell.get_inner_z(hh)
        let ro = self.get_outer_r(hh)
        let zo = self.get_outer_z(hh)
        let z4 = zo + (r4 - ro) * (zo - zi) / (ro - ri)
        let z_in_ladder = abs(z4 - avg.ladderZ[il])
        let z_in_module = z_in_ladder - module_length * Float32(
            Int(z_in_ladder / module_length)
        )
        let gap = z_in_module < module_tolerance or \
            z_in_module > (module_length - module_tolerance)
        let holeP = z4 > avg.ladderMaxZ[il] and z4 < avg.endCapZ[0]
        let holeN = z4 < avg.ladderMinZ[il] and z4 > avg.endCapZ[1]
        return gap or holeP or holeN

    fn find_ntuplets[DEPTH: Int](
        self,
        hh: Hits,
        cells: UnsafePointer[GPUCACell],
        mut cellTracks: CellTracksVector,
        mut foundNtuplets: HitContainer,
        mut apc: AtomicPairCounter,
        quality: UnsafePointer[pixelTrack.Quality],
        mut tmpNtuplet: TmpTuple,
        minHitsPerNtuplet: UInt32,
        startAt0: Bool
    ):
        @parameter
        if DEPTH == 0:
            print("ERROR: GPUCACell::find_ntuplets reached full depth!")
            assert False
            return
    
        var doubletId = self.theDoubletId.cast[UInt32]()
        _ = tmpNtuplet.push_back_unsafe(doubletId)
        assert len(tmpNtuplet) <= 4
    
        var last = True
        let nNeighbors = len(self.outerNeighbors())
        var j: Int = 0
        while j < nNeighbors:
            let otherCell = self.outerNeighbors()[j.cast[Int32]()]
            let otherIdx = otherCell.cast[Int]()
            if (cells + otherIdx)[].theDoubletId < 0:
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
    
        if last:
            if UInt32(len(tmpNtuplet)) >= minHitsPerNtuplet - 1:
                var accept = True
                @parameter
                if is_defined["ONLY_TRIPLETS_IN_HOLE"]():
                    let firstCell = tmpNtuplet[0]
                    let inner = (cells + firstCell.cast[Int]())[]
                    accept = len(tmpNtuplet) >= 3 or \
                        (startAt0 and self.hole4(hh, inner)) or \
                        (not startAt0 and self.hole0(hh, inner))
                if accept:
                    var hits = InlineArray[GPUCACell.hindex_type, 6](fill=0)
                    var nh: UInt32 = 0
                    let tupleSize = len(tmpNtuplet)
                    var i: Int = 0
                    while i < tupleSize:
                        let cellIdx = tmpNtuplet[i.cast[Int32]()]
                        hits[nh.cast[Int]()] = (cells + cellIdx.cast[Int]())[].theInnerHitId
                        nh += 1
                        i += 1
                    hits[nh.cast[Int]()] = self.theOuterHitId
                    let it = foundNtuplets.bulkFill(
                        apc,
                        hits.unsafe_ptr(),
                        UInt32(tupleSize + 1),
                    )
                    if it >= 0:
                        let tid = it.cast[UInt16]()
                        i = 0
                        while i < tupleSize:
                            let cellIdx = tmpNtuplet[i.cast[Int32]()]
                            (cells + cellIdx.cast[Int]())[].addTrack(
                                tid,
                                cellTracks,
                            )
                            i += 1
                        quality[it] = trackQuality.bad
    
        _ = tmpNtuplet.pop_back()
        assert len(tmpNtuplet) < 4
