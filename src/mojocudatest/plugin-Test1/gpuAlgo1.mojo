# Mojo port of pixeltrack-standalone/src/cudatest/plugin-Test1/gpuAlgo1.cu
#
# Mirrors the CUDA reference 1:1: every GPU buffer is allocated through the
# cms-style device_unique_ptr, the kernels keep the original signatures and
# output destinations, and the function returns d_a just like the C++ source.
# The host-side initialisation + cudaMemcpyAsync from the reference is
# replaced with an on-device init kernel, because the Mojo CUDA layer in
# this project does not expose cudaMemcpyAsync.
from builtin.dtype import DType
from std.gpu.host import DeviceContext

from MojoBridge.DTypes import Typeable
from CUDACompat import CUDAStreamType, cudaStreamDefault
from CUDAAppContext import CUDAAppContext
from device_unique_ptr import (
    unique_ptr as device_unique_ptr,
    make_device_unique,
    _DeviceAllocation,
)
from host_unique_ptr import unique_ptr as host_unique_ptr


alias cudaStream_t = CUDAStreamType
alias NUM_VALUES = 1000


# Typeable wrapper around device_unique_ptr[Float32] so it can be stored in
# a Product[T] (Product requires T: Movable & Typeable).
struct TypeableFloatBuffer(Defaultable, Movable, Typeable):
    var ptr: device_unique_ptr[Float32]

    @always_inline
    fn __init__(out self):
        self.ptr = device_unique_ptr[Float32](_DeviceAllocation[Float32]())

    @always_inline
    fn __init__(out self, var ptr: device_unique_ptr[Float32]):
        self.ptr = ptr^

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self.ptr = take.ptr^

    @always_inline
    fn get(self) -> UnsafePointer[Float32, MutAnyOrigin]:
        return self.ptr.get()

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "TypeableFloatBuffer"


# ── GPU kernels ──────────────────────────────────────────────────────────────

# Replaces the host-side `for (i ..) { h_a[i] = i; h_b[i] = i*i; }` plus
# the two cudaMemcpyAsync calls from the C++ reference.
fn initInputs_kernel(
    a: UnsafePointer[Float32, MutAnyOrigin],
    b: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var i = Int(thread_idx.x + block_idx.x * block_dim.x)
    if i < Int(numElements):
        var x = Float32(i)
        a[i] = x
        b[i] = x * x


# Element-wise copy. Not used by gpuAlgo1 itself; re-exported because
# downstream test code imports it from this module.
fn copy_kernel_float(
    src: UnsafePointer[Float32, MutAnyOrigin],
    dst: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var i = Int(thread_idx.x + block_idx.x * block_dim.x)
    if i < Int(numElements):
        dst[i] = src[i]


fn vectorAdd_kernel(
    a: UnsafePointer[Float32, MutAnyOrigin],
    b: UnsafePointer[Float32, MutAnyOrigin],
    c: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var i = Int(thread_idx.x + block_idx.x * block_dim.x)
    if i < Int(numElements):
        c[i] = a[i] + b[i]


fn vectorProd_kernel(
    a: UnsafePointer[Float32, MutAnyOrigin],
    b: UnsafePointer[Float32, MutAnyOrigin],
    c: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var row = Int(thread_idx.y + block_idx.y * block_dim.y)
    var col = Int(thread_idx.x + block_idx.x * block_dim.x)
    var n = Int(numElements)
    if row < n and col < n:
        c[row * n + col] = a[row] * b[col]


fn matrixMul_kernel(
    a: UnsafePointer[Float32, MutAnyOrigin],
    b: UnsafePointer[Float32, MutAnyOrigin],
    c: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var row = Int(thread_idx.y + block_idx.y * block_dim.y)
    var col = Int(thread_idx.x + block_idx.x * block_dim.x)
    var n = Int(numElements)
    if row < n and col < n:
        var tmp: Float32 = 0
        for i in range(n):
            tmp += a[row * n + i] * b[i * n + col]
        c[row * n + col] = tmp


fn matrixMulVector_kernel(
    a: UnsafePointer[Float32, MutAnyOrigin],
    b: UnsafePointer[Float32, MutAnyOrigin],
    c: UnsafePointer[Float32, MutAnyOrigin],
    numElements: Int32,
):
    from std.gpu import thread_idx, block_idx, block_dim
    var row = Int(thread_idx.x + block_idx.x * block_dim.x)
    var n = Int(numElements)
    if row < n:
        var tmp: Float32 = 0
        for i in range(n):
            tmp += a[row * n + i] * b[i]
        c[row] = tmp


# ── Host-side algorithm ─────────────────────────────────────────────────────
fn gpuAlgo1(
    stream: cudaStream_t, mut cuda_ctx: CUDAAppContext
) raises -> device_unique_ptr[Float32]:
    var d_a = make_device_unique[Float32](
        UInt(NUM_VALUES), cuda_ctx.device_state, stream
    )
    var d_b = make_device_unique[Float32](
        UInt(NUM_VALUES), cuda_ctx.device_state, stream
    )

    var gpu_ctx = DeviceContext(api="cuda")

    alias threadsPerBlock = 32
    alias blocksPerGrid = (NUM_VALUES + threadsPerBlock - 1) // threadsPerBlock

    gpu_ctx.enqueue_function[initInputs_kernel, initInputs_kernel](
        d_a.get(), d_b.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid,), block_dim=(threadsPerBlock,),
    )

    var d_c = make_device_unique[Float32](
        UInt(NUM_VALUES), cuda_ctx.device_state, stream
    )
    gpu_ctx.enqueue_function[vectorAdd_kernel, vectorAdd_kernel](
        d_a.get(), d_b.get(), d_c.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid,), block_dim=(threadsPerBlock,),
    )

    var d_ma = make_device_unique[Float32](
        UInt(NUM_VALUES * NUM_VALUES), cuda_ctx.device_state, stream
    )
    var d_mb = make_device_unique[Float32](
        UInt(NUM_VALUES * NUM_VALUES), cuda_ctx.device_state, stream
    )
    var d_mc = make_device_unique[Float32](
        UInt(NUM_VALUES * NUM_VALUES), cuda_ctx.device_state, stream
    )

    var threadsPerBlock_x: Int = NUM_VALUES
    var threadsPerBlock_y: Int = NUM_VALUES
    var blocksPerGrid_x: Int = 1
    var blocksPerGrid_y: Int = 1
    if NUM_VALUES * NUM_VALUES > 32:
        threadsPerBlock_x = 32
        threadsPerBlock_y = 32
        blocksPerGrid_x = (NUM_VALUES + 31) // 32
        blocksPerGrid_y = (NUM_VALUES + 31) // 32

    gpu_ctx.enqueue_function[vectorProd_kernel, vectorProd_kernel](
        d_a.get(), d_b.get(), d_ma.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid_x, blocksPerGrid_y),
        block_dim=(threadsPerBlock_x, threadsPerBlock_y),
    )
    gpu_ctx.enqueue_function[vectorProd_kernel, vectorProd_kernel](
        d_a.get(), d_c.get(), d_mb.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid_x, blocksPerGrid_y),
        block_dim=(threadsPerBlock_x, threadsPerBlock_y),
    )
    gpu_ctx.enqueue_function[matrixMul_kernel, matrixMul_kernel](
        d_ma.get(), d_mb.get(), d_mc.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid_x, blocksPerGrid_y),
        block_dim=(threadsPerBlock_x, threadsPerBlock_y),
    )

    gpu_ctx.enqueue_function[matrixMulVector_kernel, matrixMulVector_kernel](
        d_mc.get(), d_b.get(), d_c.get(), Int32(NUM_VALUES),
        grid_dim=(blocksPerGrid,), block_dim=(threadsPerBlock,),
    )
    gpu_ctx.synchronize()

    return d_a^
