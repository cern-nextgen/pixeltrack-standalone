from MojoSerial.CUDACore.CUDACompat import CUDACompat
from MojoSerial.MojoBridge.DTypes import Float
from MojoSerial.plugin_PixelVertexFinding.gpuVertexFinder import ZVertices, WorkSpace

alias verbose: Bool = False  # in principle the compiler should optmize out if false


@always_inline
fn splitVertices(
    pdata: UnsafePointer[ZVertices], pws: UnsafePointer[WorkSpace], maxChi2: Float
):
    ref data = pdata[]
    ref ws = pws[]
    var nt = ws.ntrks
    ref zt: InlineArray[Float, UInt(WorkSpace.MAXTRACKS)] = ws.zt
    ref ezt2: InlineArray[Float, UInt(WorkSpace.MAXTRACKS)] = ws.ezt2
    ref zv: InlineArray[Float, UInt(ZVertices.MAXVTX)] = data.zv
    ref wv: InlineArray[Float, UInt(ZVertices.MAXVTX)] = data.wv
    ref chi2: InlineArray[Float, UInt(ZVertices.MAXVTX)] = data.chi2
    ref nvFinal: UInt32 = data.nvFinal

    ref nn: InlineArray[Int32, UInt(ZVertices.MAXTRACKS)] = data.ndof
    ref iv: InlineArray[Int32, UInt(WorkSpace.MAXTRACKS)] = ws.iv

    # one vertex per block
    for kv in range(nvFinal):
        if nn[kv] < 4:
            continue
        if chi2[kv] < maxChi2 * Float(nn[kv]):
            continue

        alias MAXTK: Int = 512
        debug_assert(nn[kv] < MAXTK)
        if nn[kv] >= MAXTK:
            continue  # too bad FIXME
        var it = InlineArray[UInt32, MAXTK](uninitialized=True)  # track index
        var zz = InlineArray[Float, MAXTK](uninitialized=True)  # z pos
        var newV = InlineArray[UInt8, MAXTK](uninitialized=True)  # 0 or 1
        var ww = InlineArray[Float, MAXTK](uninitialized=True)  # z weight

        var nq: UInt32  # number of track for this vertex
        nq = 0

        # copy to local
        for k in range(nt):
            if iv[k] == Int32(kv):
                var old = CUDACompat.atomicInc(UnsafePointer(to=nq), UInt32(MAXTK))
                zz[Int(old)] = zt[k] - zv[kv]
                newV[Int(old)] = 0 if zz[Int(old)] < 0 else 1
                ww[Int(old)] = 1.0 / ezt2[k]
                it[Int(old)] = k

        var znew: InlineArray[Float, 2] = InlineArray[Float, 2](0.0, 0.0)  # the new vertices
        var wnew: InlineArray[Float, 2] = InlineArray[Float, 2](0.0, 0.0)  # the new vertices

        debug_assert(Int32(nq) == nn[kv] + 1)

        var maxiter: Int32 = 20
        # kt-min....
        var more: Bool = True
        while more:
            more = False

            znew[0] = 0
            znew[1] = 0
            wnew[0] = 0
            wnew[1] = 0

            for k in range(nq):
                var i = newV[Int(k)]
                _ = CUDACompat.atomicAdd(
                    UnsafePointer(to=znew[Int(i)]), zz[Int(k)] * ww[Int(k)]
                )
                _ = CUDACompat.atomicAdd(UnsafePointer(to=wnew[Int(i)]), ww[Int(k)])

            znew[0] /= wnew[0]
            znew[1] /= wnew[1]

            for k in range(nq):
                var d0 = abs(zz[Int(k)] - znew[0])
                var d1 = abs(zz[Int(k)] - znew[1])
                var newer: UInt8 = 0 if d0 < d1 else 1
                more |= newer != newV[Int(k)]
                newV[Int(k)] = newer
            maxiter -= 1
            if maxiter <= 0:
                more = False

        # avoid empty vertices
        if wnew[0] == 0 or wnew[1] == 0:
            continue

        # quality cut
        var dist2 = (znew[0] - znew[1]) * (znew[0] - znew[1])

        var chi2Dist = dist2 / (1.0 / wnew[0] + 1.0 / wnew[1])

        @parameter
        if verbose:
            print("inter", 20 - maxiter, chi2Dist, dist2 * wv[kv])

        if chi2Dist < 4:
            continue

        # get a new global vertex
        var igv: UInt32
        igv = CUDACompat.atomicAdd(UnsafePointer(to=ws.nvIntermediate), UInt32(1))

        for k in range(nq):
            if newV[Int(k)] == 1:
                iv[Int(it[Int(k)])] = Int32(igv)

    # loop on vertices


@always_inline
fn splitVerticesKernel(
    pdata: UnsafePointer[ZVertices], pws: UnsafePointer[WorkSpace], maxChi2: Float
):
    splitVertices(pdata, pws, maxChi2)
