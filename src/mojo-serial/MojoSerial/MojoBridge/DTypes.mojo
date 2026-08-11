from memory import bitcast

alias SizeType = UInt32  # size_t
alias Short = Int16  # short
alias Float = Float32  # float
alias Double = Float64  # double
alias Char = Int8  # char
alias UChar = UInt8  # unsigned char

# CUDA Driver API result type (mirrors CUresult enum values from CUDA headers).
alias CUresult = Int32

alias CUDA_SUCCESS: CUresult = 0
alias CUDA_ERROR_INVALID_VALUE: CUresult = 1
alias CUDA_ERROR_OUT_OF_MEMORY: CUresult = 2
alias CUDA_ERROR_NOT_INITIALIZED: CUresult = 3
alias CUDA_ERROR_DEINITIALIZED: CUresult = 4
alias CUDA_ERROR_PROFILER_DISABLED: CUresult = 5
alias CUDA_ERROR_PROFILER_NOT_INITIALIZED: CUresult = 6
alias CUDA_ERROR_PROFILER_ALREADY_STARTED: CUresult = 7
alias CUDA_ERROR_PROFILER_ALREADY_STOPPED: CUresult = 8
alias CUDA_ERROR_STUB_LIBRARY: CUresult = 34
alias CUDA_ERROR_DEVICE_UNAVAILABLE: CUresult = 46
alias CUDA_ERROR_NO_DEVICE: CUresult = 100
alias CUDA_ERROR_INVALID_DEVICE: CUresult = 101
alias CUDA_ERROR_DEVICE_NOT_LICENSED: CUresult = 102
alias CUDA_ERROR_INVALID_IMAGE: CUresult = 200
alias CUDA_ERROR_INVALID_CONTEXT: CUresult = 201
alias CUDA_ERROR_CONTEXT_ALREADY_CURRENT: CUresult = 202
alias CUDA_ERROR_MAP_FAILED: CUresult = 205
alias CUDA_ERROR_UNMAP_FAILED: CUresult = 206
alias CUDA_ERROR_ARRAY_IS_MAPPED: CUresult = 207
alias CUDA_ERROR_ALREADY_MAPPED: CUresult = 208
alias CUDA_ERROR_NO_BINARY_FOR_GPU: CUresult = 209
alias CUDA_ERROR_ALREADY_ACQUIRED: CUresult = 210
alias CUDA_ERROR_NOT_MAPPED: CUresult = 211
alias CUDA_ERROR_NOT_MAPPED_AS_ARRAY: CUresult = 212
alias CUDA_ERROR_NOT_MAPPED_AS_POINTER: CUresult = 213
alias CUDA_ERROR_ECC_UNCORRECTABLE: CUresult = 214
alias CUDA_ERROR_UNSUPPORTED_LIMIT: CUresult = 215
alias CUDA_ERROR_CONTEXT_ALREADY_IN_USE: CUresult = 216
alias CUDA_ERROR_PEER_ACCESS_UNSUPPORTED: CUresult = 217
alias CUDA_ERROR_INVALID_PTX: CUresult = 218
alias CUDA_ERROR_INVALID_GRAPHICS_CONTEXT: CUresult = 219
alias CUDA_ERROR_NVLINK_UNCORRECTABLE: CUresult = 220
alias CUDA_ERROR_JIT_COMPILER_NOT_FOUND: CUresult = 221
alias CUDA_ERROR_UNSUPPORTED_PTX_VERSION: CUresult = 222
alias CUDA_ERROR_JIT_COMPILATION_DISABLED: CUresult = 223
alias CUDA_ERROR_UNSUPPORTED_EXEC_AFFINITY: CUresult = 224
alias CUDA_ERROR_UNSUPPORTED_DEVSIDE_SYNC: CUresult = 225
alias CUDA_ERROR_INVALID_SOURCE: CUresult = 300
alias CUDA_ERROR_FILE_NOT_FOUND: CUresult = 301
alias CUDA_ERROR_SHARED_OBJECT_SYMBOL_NOT_FOUND: CUresult = 302
alias CUDA_ERROR_SHARED_OBJECT_INIT_FAILED: CUresult = 303
alias CUDA_ERROR_OPERATING_SYSTEM: CUresult = 304
alias CUDA_ERROR_INVALID_HANDLE: CUresult = 400
alias CUDA_ERROR_ILLEGAL_STATE: CUresult = 401
alias CUDA_ERROR_LOSSY_QUERY: CUresult = 402
alias CUDA_ERROR_NOT_FOUND: CUresult = 500
alias CUDA_ERROR_NOT_READY: CUresult = 600
alias CUDA_ERROR_ILLEGAL_ADDRESS: CUresult = 700
alias CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES: CUresult = 701
alias CUDA_ERROR_LAUNCH_TIMEOUT: CUresult = 702
alias CUDA_ERROR_LAUNCH_INCOMPATIBLE_TEXTURING: CUresult = 703
alias CUDA_ERROR_PEER_ACCESS_ALREADY_ENABLED: CUresult = 704
alias CUDA_ERROR_PEER_ACCESS_NOT_ENABLED: CUresult = 705
alias CUDA_ERROR_PRIMARY_CONTEXT_ACTIVE: CUresult = 708
alias CUDA_ERROR_CONTEXT_IS_DESTROYED: CUresult = 709
alias CUDA_ERROR_ASSERT: CUresult = 710
alias CUDA_ERROR_TOO_MANY_PEERS: CUresult = 711
alias CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED: CUresult = 712
alias CUDA_ERROR_HOST_MEMORY_NOT_REGISTERED: CUresult = 713
alias CUDA_ERROR_HARDWARE_STACK_ERROR: CUresult = 714
alias CUDA_ERROR_ILLEGAL_INSTRUCTION: CUresult = 715
alias CUDA_ERROR_MISALIGNED_ADDRESS: CUresult = 716
alias CUDA_ERROR_INVALID_ADDRESS_SPACE: CUresult = 717
alias CUDA_ERROR_INVALID_PC: CUresult = 718
alias CUDA_ERROR_LAUNCH_FAILED: CUresult = 719
alias CUDA_ERROR_COOPERATIVE_LAUNCH_TOO_LARGE: CUresult = 720
alias CUDA_ERROR_NOT_PERMITTED: CUresult = 800
alias CUDA_ERROR_NOT_SUPPORTED: CUresult = 801
alias CUDA_ERROR_SYSTEM_NOT_READY: CUresult = 802
alias CUDA_ERROR_SYSTEM_DRIVER_MISMATCH: CUresult = 803
alias CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE: CUresult = 804
alias CUDA_ERROR_MPS_CONNECTION_FAILED: CUresult = 805
alias CUDA_ERROR_MPS_RPC_FAILURE: CUresult = 806
alias CUDA_ERROR_MPS_SERVER_NOT_READY: CUresult = 807
alias CUDA_ERROR_MPS_MAX_CLIENTS_REACHED: CUresult = 808
alias CUDA_ERROR_MPS_MAX_CONNECTIONS_REACHED: CUresult = 809
alias CUDA_ERROR_MPS_CLIENT_TERMINATED: CUresult = 810
alias CUDA_ERROR_CDP_NOT_SUPPORTED: CUresult = 811
alias CUDA_ERROR_CDP_VERSION_MISMATCH: CUresult = 812
alias CUDA_ERROR_STREAM_CAPTURE_UNSUPPORTED: CUresult = 900
alias CUDA_ERROR_STREAM_CAPTURE_INVALIDATED: CUresult = 901
alias CUDA_ERROR_STREAM_CAPTURE_MERGE: CUresult = 902
alias CUDA_ERROR_STREAM_CAPTURE_UNMATCHED: CUresult = 903
alias CUDA_ERROR_STREAM_CAPTURE_UNJOINED: CUresult = 904
alias CUDA_ERROR_STREAM_CAPTURE_ISOLATION: CUresult = 905
alias CUDA_ERROR_STREAM_CAPTURE_IMPLICIT: CUresult = 906
alias CUDA_ERROR_CAPTURED_EVENT: CUresult = 907
alias CUDA_ERROR_STREAM_CAPTURE_WRONG_THREAD: CUresult = 908
alias CUDA_ERROR_TIMEOUT: CUresult = 909
alias CUDA_ERROR_GRAPH_EXEC_UPDATE_FAILURE: CUresult = 910
alias CUDA_ERROR_EXTERNAL_DEVICE: CUresult = 911
alias CUDA_ERROR_INVALID_CLUSTER_SIZE: CUresult = 912
alias CUDA_ERROR_FUNCTION_NOT_LOADED: CUresult = 913
alias CUDA_ERROR_INVALID_RESOURCE_TYPE: CUresult = 914
alias CUDA_ERROR_INVALID_RESOURCE_CONFIGURATION: CUresult = 915
alias CUDA_ERROR_UNKNOWN: CUresult = 999
alias CUDA_ERROR_INVALID_PTX_JIT_INPUT: CUresult = 10000
alias CUDA_ERROR_INVALID_PTX_JIT_OPTION: CUresult = 10001
alias CUDA_ERROR_INVALID_PTX_JIT_LOG: CUresult = 10002
alias CUDA_ERROR_PTX_JIT_COMPILER_NOT_FOUND: CUresult = 10003
alias CUDA_ERROR_UNSUPPORTED_PTX_JIT_VERSION: CUresult = 10004
alias CUDA_ERROR_PTX_JIT_COMPILATION_DISABLED: CUresult = 10005
alias CUDA_ERROR_PTX_JIT_COMPILER_UNSUPPORTED_OPERATION: CUresult = 10006


fn cuResultName(result: CUresult) -> String:
    if result == CUDA_SUCCESS:
        return "CUDA_SUCCESS"
    elif result == CUDA_ERROR_INVALID_VALUE:
        return "CUDA_ERROR_INVALID_VALUE"
    elif result == CUDA_ERROR_OUT_OF_MEMORY:
        return "CUDA_ERROR_OUT_OF_MEMORY"
    elif result == CUDA_ERROR_NOT_INITIALIZED:
        return "CUDA_ERROR_NOT_INITIALIZED"
    elif result == CUDA_ERROR_DEINITIALIZED:
        return "CUDA_ERROR_DEINITIALIZED"
    elif result == CUDA_ERROR_NO_DEVICE:
        return "CUDA_ERROR_NO_DEVICE"
    elif result == CUDA_ERROR_INVALID_DEVICE:
        return "CUDA_ERROR_INVALID_DEVICE"
    elif result == CUDA_ERROR_NOT_SUPPORTED:
        return "CUDA_ERROR_NOT_SUPPORTED"
    elif result == CUDA_ERROR_UNKNOWN:
        return "CUDA_ERROR_UNKNOWN"
    return "CUresult(" + String(result) + ")"


fn cuResultMessage(result: CUresult) -> String:
    if result == CUDA_SUCCESS:
        return "success"
    elif result == CUDA_ERROR_INVALID_VALUE:
        return "invalid value"
    elif result == CUDA_ERROR_OUT_OF_MEMORY:
        return "out of memory"
    elif result == CUDA_ERROR_NOT_INITIALIZED:
        return "driver not initialized"
    elif result == CUDA_ERROR_DEINITIALIZED:
        return "driver deinitialized"
    elif result == CUDA_ERROR_NO_DEVICE:
        return "no CUDA-capable device detected"
    elif result == CUDA_ERROR_INVALID_DEVICE:
        return "invalid device"
    elif result == CUDA_ERROR_NOT_SUPPORTED:
        return "operation not supported"
    elif result == CUDA_ERROR_UNKNOWN:
        return "unknown CUDA driver error"
    return "CUDA driver error code " + String(result)


# this trait is essential for supporting the framework
# currently, the framework uses some clever rebind trickery to bypass statically typed objects and store arbitrary objects within a container, but to have the same type flexibility, we must also be able to identify objects by type
trait Typeable:
    @always_inline
    @staticmethod
    fn dtype() -> String:
        ...


fn hex_to_float[fld: Int32]() -> Float:
    return bitcast[src_dtype = DType.int32, src_width=1, DType.float32](fld)


fn signed_to_unsigned[T: DType]() -> DType:
    @parameter
    if T == DType.int8 or T == DType.uint8:
        return DType.uint8
    elif T == DType.int16 or T == DType.uint16:
        return DType.uint16
    elif T == DType.int32 or T == DType.uint32:
        return DType.uint32
    elif T == DType.int64 or T == DType.uint64:
        return DType.uint64
    elif T == DType.int128 or T == DType.uint128:
        return DType.uint128
    elif T == DType.int256 or T == DType.uint256:
        return DType.uint256
    return DType.invalid


@always_inline
fn enumerate[T: Movable & Copyable](K: Span[T]) -> List[Tuple[Int, T]]:
    var L: List[Tuple[Int, T]] = []
    for i in range(len(K)):
        L.append((i, K[i]))
    return L


@fieldwise_init
@register_passable("trivial")
struct TypeableInt(Copyable, Movable, Typeable):
    var val: Int

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "TypeableInt"


@fieldwise_init
@register_passable("trivial")
struct TypeableUInt(Copyable, Movable, Typeable):
    var val: UInt

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "TypeableUInt"
