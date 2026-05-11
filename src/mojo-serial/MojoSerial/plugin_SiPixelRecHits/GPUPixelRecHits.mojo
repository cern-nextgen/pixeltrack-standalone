from math import sqrt
from utils.numerics import max_finite

from MojoSerial.DataFormats.BeamSpotPOD import BeamSpotPOD
from MojoSerial.DataFormats.ApproxAtan2 import ApproxAtan2
from MojoSerial.CUDADataFormats.TrackingRecHit2DSOAView import (
    TrackingRecHit2DSOAView,
)
from MojoSerial.Geometry.Phase1PixelTopology import AverageGeometry

import MojoSerial.CUDADataFormats.TrackingRecHit2DHeterogeneous as TrackingRecHit2DHeterogeneous
import MojoSerial.CUDADataFormats.SiPixelDigisSoA as SiPixelDigisSoA
import MojoSerial.CUDADataFormats.SiPixelClustersSoA as SiPixelClustersSoA
import MojoSerial.CondFormats.PixelCPEforGPU as PixelCPEforGPU


fn getHits(
    cpeParams: UnsafePointer[PixelCPEforGPU.ParamsOnGPU],
    bs: UnsafePointer[BeamSpotPOD],
    pdigis: UnsafePointer[SiPixelDigisSoA.DeviceConstView],
    numElements: UInt32,
    pclusters: UnsafePointer[SiPixelClustersSoA.DeviceConstView],
    phits: UnsafePointer[TrackingRecHit2DSOAView],
):
    # FIXME
    # the compiler seems NOT to optimize loads from views (even in a simple test case)
    # The whole gimnastic here of copying or not is a pure heuristic exercise that seems to produce the fastest code with the above signature
    # not using views (passing a gazzilion of array pointers) seems to produce the fastest code (but it is harder to mantain)

    debug_assert(phits)
    debug_assert(cpeParams)

    ref hits = phits[]

    ref digis = pdigis[]  # the copy is intentional!
    ref clusters = pclusters[]

    # copy average geometry corrected by beamspot . FIXME (move it somewhere else???)

    ref agc = hits.averageGeometry()
    ref ag = cpeParams[].averageGeometry()
    for il in range(AverageGeometry.numberOfLaddersInBarrel):
        agc.ladderZ[il] = ag.ladderZ[il] - bs[].z
        agc.ladderX[il] = ag.ladderX[il] - bs[].x
        agc.ladderY[il] = ag.ladderY[il] - bs[].y
        agc.ladderR[il] = sqrt(
            agc.ladderX[il] * agc.ladderX[il]
            + agc.ladderY[il] * agc.ladderY[il]
        )
        agc.ladderMinZ[il] = ag.ladderMinZ[il] - bs[].z
        agc.ladderMaxZ[il] = ag.ladderMaxZ[il] - bs[].z

    agc.endCapZ[0] = ag.endCapZ[0] - bs[].z
    agc.endCapZ[1] = ag.endCapZ[1] - bs[].z

    # to be moved in common namespace...
    alias InvId: UInt16 = 9999  # must be > MaxNumModules
    alias MaxHitsInIter = Int(PixelCPEforGPU.MaxHitsInIter)

    alias ClusParams = PixelCPEforGPU.ClusParams

    # as usual one block per module
    var clusParams = ClusParams()

    var firstModule: UInt32 = 0
    var endModule = Int(clusters.moduleStart(0))
    for module in range(firstModule, endModule):
        var me = Int(clusters.moduleId(module))
        var nclus = Int(clusters.clusInModule(me))

        if nclus == 0:
            continue

        var endClus = nclus
        for startClus in range(0, endClus, MaxHitsInIter):
            var first = clusters.moduleStart(1 + module)

            var nClusInIter: Int = min(MaxHitsInIter, endClus - startClus)
            var lastClus: Int = startClus + nClusInIter

            debug_assert(nClusInIter <= nclus)
            debug_assert(nClusInIter > 0)
            debug_assert(lastClus <= nclus)

            debug_assert(
                nclus > MaxHitsInIter
                or (
                    0 == startClus
                    and nClusInIter == nclus
                    and lastClus == nclus
                )
            )

            # init
            for ic in range(nClusInIter):
                clusParams.minRow[ic] = max_finite[DType.uint32]()
                clusParams.maxRow[ic] = 0
                clusParams.minCol[ic] = max_finite[DType.uint32]()
                clusParams.maxCol[ic] = 0
                clusParams.charge[ic] = 0
                clusParams.Q_f_X[ic] = 0
                clusParams.Q_l_X[ic] = 0
                clusParams.Q_f_Y[ic] = 0
                clusParams.Q_l_Y[ic] = 0

            # one thead per "digi"

            for i in range(first, Int(numElements)):
                var id = digis.moduleInd(i)
                if id == InvId:
                    continue  # not valid
                if id != me:
                    break  # end of module

                var cl = Int(digis.clus(i))
                if cl < startClus or cl >= lastClus:
                    continue
                var x = UInt32(digis.xx(i))
                var y = UInt32(digis.yy(i))
                cl -= startClus

                debug_assert(cl >= 0)
                debug_assert(cl < MaxHitsInIter)

                clusParams.minRow[cl] = min(clusParams.minRow[cl], x)
                clusParams.maxRow[cl] = max(clusParams.maxRow[cl], x)
                clusParams.minCol[cl] = min(clusParams.minCol[cl], y)
                clusParams.maxCol[cl] = max(clusParams.maxCol[cl], y)

            # pixmx is not available in the binary dumps
            var pixmx = max_finite[DType.uint16]()
            for i in range(first, Int(numElements)):
                var id = digis.moduleInd(i)
                if id == InvId:
                    continue  # not valid
                if id != me:
                    break  # end of module

                var cl = Int(digis.clus(i))
                if cl < startClus or cl >= lastClus:
                    continue

                cl -= startClus
                debug_assert(cl >= 0)
                debug_assert(cl < MaxHitsInIter)

                var x = UInt32(digis.xx(i))
                var y = UInt32(digis.yy(i))
                var ch = Int32(min(digis.adc(i), pixmx))

                clusParams.charge[cl] += ch
                if clusParams.minRow[cl] == x:
                    clusParams.Q_f_X[cl] += ch
                if clusParams.maxRow[cl] == x:
                    clusParams.Q_l_X[cl] += ch
                if clusParams.minCol[cl] == y:
                    clusParams.Q_f_Y[cl] += ch
                if clusParams.maxCol[cl] == y:
                    clusParams.Q_l_Y[cl] += ch

            # next one cluster per thread...

            first = clusters.clusModuleStart(me) + startClus

            for ic in range(nClusInIter):
                var h = Int(first + ic)  # output index in global memory

                # this cannot happen anymore
                if h >= Int(TrackingRecHit2DSOAView.maxHits()):
                    break  # overflow...

                debug_assert(h < Int(hits.nHits()))
                debug_assert(h < Int(clusters.clusModuleStart(me + 1)))

                PixelCPEforGPU.position(
                    cpeParams[].commonParams(),
                    cpeParams[].detParams(me),
                    clusParams,
                    ic,
                )
                PixelCPEforGPU.errorFromDB(
                    cpeParams[].commonParams(),
                    cpeParams[].detParams(me),
                    clusParams,
                    ic,
                )

                # store it

                hits.charge(h) = clusParams.charge[ic]

                hits.detectorIndex(h) = me

                var xl: Float32
                var yl: Float32

                xl = clusParams.xpos[ic]
                hits.xLocal(h) = xl

                yl = clusParams.ypos[ic]
                hits.yLocal(h) = yl

                hits.clusterSizeX(h) = clusParams.xsize[ic]
                hits.clusterSizeY(h) = clusParams.ysize[ic]

                hits.xerrLocal(h) = clusParams.xerr[ic] * clusParams.xerr[ic]
                hits.yerrLocal(h) = clusParams.yerr[ic] * clusParams.yerr[ic]

                # keep it local for computations

                var xg: Float32 = 0
                var yg: Float32 = 0
                var zg: Float32 = 0

                # to global and compute phi...
                cpeParams[].detParams(me).frame.toGlobal(xl, yl, xg, yg, zg)
                # here correct for the beamspot...
                xg -= bs[].x
                yg -= bs[].y
                zg -= bs[].z

                hits.xGlobal(h) = xg
                hits.yGlobal(h) = yg
                hits.zGlobal(h) = zg

                hits.rGlobal(h) = sqrt(xg * xg + yg * yg)
                hits.iphi(h) = ApproxAtan2.unsafe_atan2s[7](yg, xg)
