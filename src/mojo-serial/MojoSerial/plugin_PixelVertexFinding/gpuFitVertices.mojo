from MojoSerial.CUDACore.CUDACompat import CUDACompat
from MojoSerial.MojoBridge.DTypes import Float
from MojoSerial.plugin_PixelVertexFinding.gpuVertexFinder import ZVertices, WorkSpace

alias verbose: Bool = False  # in principle the compiler should optmize out if false


@always_inline
fn fitVertices(
    pdata: UnsafePointer[ZVertices],
    pws: UnsafePointer[WorkSpace],
    chi2Max: Float,  # for outlier rejection
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
    var nvIntermediate: UInt32 = ws.nvIntermediate

    ref nn: InlineArray[Int32, UInt(ZVertices.MAXTRACKS)] = data.ndof
    ref iv: InlineArray[Int32, UInt(WorkSpace.MAXTRACKS)] = ws.iv

    debug_assert(nvFinal <= nvIntermediate)
    nvFinal = nvIntermediate
    var foundClusters = nvFinal

    # zero
    for i in range(foundClusters):
        zv[i] = 0
        wv[i] = 0
        chi2[i] = 0

    # only for test
    var noise: Int32 = 0

    @parameter
    if verbose:
        noise = 0

    # compute cluster location
    for i in range(nt):
        if iv[i] > 9990:

            @parameter
            if verbose:
                _ = CUDACompat.atomicAdd(UnsafePointer(to=noise), Int32(1))
            continue
        debug_assert(iv[i] >= 0)
        debug_assert(iv[i] < Int32(foundClusters))
        var w = 1.0 / ezt2[i]
        _ = CUDACompat.atomicAdd(UnsafePointer(to=zv[Int(iv[i])]), zt[i] * w)
        _ = CUDACompat.atomicAdd(UnsafePointer(to=wv[Int(iv[i])]), w)

    # reuse nn
    for i in range(foundClusters):
        debug_assert(wv[i] > 0.0)
        zv[i] /= wv[i]
        nn[i] = -1  # ndof

    # compute chi2
    for i in range(nt):
        if iv[i] > 9990:
            continue

        var c2 = zv[Int(iv[i])] - zt[i]
        c2 *= c2 / ezt2[i]
        if c2 > chi2Max:
            iv[i] = 9999
            continue
        _ = CUDACompat.atomicAdd(UnsafePointer(to=chi2[Int(iv[i])]), c2)
        _ = CUDACompat.atomicAdd(UnsafePointer(to=nn[Int(iv[i])]), Int32(1))

    for i in range(foundClusters):
        if nn[i] > 0:
            wv[i] *= Float(nn[i]) / chi2[i]

    @parameter
    if verbose:
        print("found", foundClusters, "proto clusters ")

    @parameter
    if verbose:
        print("and", noise, "noise")


@always_inline
fn fitVerticesKernel(
    pdata: UnsafePointer[ZVertices],
    pws: UnsafePointer[WorkSpace],
    chi2Max: Float,  # for outlier rejection
):
    fitVertices(pdata, pws, chi2Max)
