from sys import is_defined

from MojoSerial.MojoBridge.DTypes import Float
from MojoSerial.plugin_PixelVertexFinding.gpuClusterTracksByDensity import (
    clusterTracksByDensity,
)
from MojoSerial.plugin_PixelVertexFinding.gpuFitVertices import fitVertices
from MojoSerial.plugin_PixelVertexFinding.gpuSortByPt2 import sortByPt2
from MojoSerial.plugin_PixelVertexFinding.gpuSplitVertices import splitVertices
from MojoSerial.plugin_PixelVertexFinding.gpuVertexFinder import ZVertices, WorkSpace

# #define THREE_KERNELS


@always_inline
fn vertexFinderOneKernel(
    pdata: UnsafePointer[ZVertices],
    pws: UnsafePointer[WorkSpace],
    minT: Int32,  # min number of neighbours to be "seed"
    eps: Float,  # max absolute distance to cluster
    errmax: Float,  # max error to be "seed"
    chi2max: Float,  # max normalized distance to cluster,
) raises:
    @parameter
    if not is_defined["THREE_KERNELS"]():
        clusterTracksByDensity(pdata, pws, minT, eps, errmax, chi2max)

        fitVertices(pdata, pws, 50.0)

        splitVertices(pdata, pws, 9.0)

        fitVertices(pdata, pws, 5000.0)

        sortByPt2(pdata, pws)
    else:
        raise "vertexFinderOneKernel is not compiled in with THREE_KERNELS defined"


@always_inline
fn vertexFinderKernel1(
    pdata: UnsafePointer[ZVertices],
    pws: UnsafePointer[WorkSpace],
    minT: Int32,  # min number of neighbours to be "seed"
    eps: Float,  # max absolute distance to cluster
    errmax: Float,  # max error to be "seed"
    chi2max: Float,  # max normalized distance to cluster,
) raises:
    @parameter
    if is_defined["THREE_KERNELS"]():
        clusterTracksByDensity(pdata, pws, minT, eps, errmax, chi2max)

        fitVertices(pdata, pws, 50.0)
    else:
        raise "vertexFinderKernel1 requires THREE_KERNELS to be defined"


@always_inline
fn vertexFinderKernel2(
    pdata: UnsafePointer[ZVertices], pws: UnsafePointer[WorkSpace]
) raises:
    @parameter
    if is_defined["THREE_KERNELS"]():
        fitVertices(pdata, pws, 5000.0)

        sortByPt2(pdata, pws)
    else:
        raise "vertexFinderKernel2 requires THREE_KERNELS to be defined"
