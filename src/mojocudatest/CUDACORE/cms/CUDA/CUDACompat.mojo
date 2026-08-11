from std.gpu.host import DeviceContext
from std.gpu.host.device_context import DeviceEvent, DeviceStream


from MojoBridge.DTypes import (
    cudaError_t,
    cudaSuccess,
    cudaErrorNotReady,
)

from utils.lock import BlockingSpinLock, BlockingScopedLock


@fieldwise_init
struct CUDAStreamType(Copyable, ImplicitlyCopyable, Defaultable, ImplicitlyDestructible, Movable):
    var stream_id: UInt64
    var stream: Optional[DeviceStream]

    @always_inline
    fn __init__(out self):
        self.stream_id = 0
        self.stream = None

    @always_inline
    fn __init__(out self, stream: DeviceStream):
        self.stream_id = 0
        self.stream = stream

    @always_inline
    fn __copyinit__(out self, copy: Self):
        self.stream_id = copy.stream_id
        self.stream = copy.stream

    @always_inline
    fn is_default(self) -> Bool:
        return self.stream_id == 0

    @always_inline
    fn get(self) raises -> DeviceStream:
        if self.stream:
            return self.stream.value()
        var ctx = DeviceContext(api="cuda")
        return ctx.stream()

    @always_inline
    fn record_event(self, event: DeviceEvent) raises:
        var actual_stream = self.get()
        actual_stream.record_event(event)

    @always_inline
    fn enqueue_wait_for(self, event: DeviceEvent) raises:
        var actual_stream = self.get()
        actual_stream.enqueue_wait_for(event)

    @always_inline
    fn synchronize(self) raises:
        var actual_stream = self.get()
        actual_stream.synchronize()

    @always_inline
    fn __eq__(self, other: Self) -> Bool:
        return self.stream_id == other.stream_id

    @always_inline
    fn __ne__(self, other: Self) -> Bool:
        return self.stream_id != other.stream_id


# Sentinel "default stream" value.
comptime cudaStreamDefault: CUDAStreamType = CUDAStreamType()


@fieldwise_init
struct CUDAEventType(Copyable, Defaultable, ImplicitlyCopyable, Movable):
    var event_id: UInt64
    var has_real_event: Bool
    var real_event: Optional[DeviceEvent]
    var runtime: UnsafePointer[CUDARuntime, MutAnyOrigin]

    @always_inline
    fn __init__(out self):
        self.event_id = 0
        self.has_real_event = False
        self.real_event = None
        self.runtime = UnsafePointer[CUDARuntime, MutAnyOrigin]()


@fieldwise_init
struct _CUDAEventState(Copyable, Defaultable, ImplicitlyCopyable, Movable):
    var expected_seq: UInt64
    var completed_seq: UInt64

    @always_inline
    fn __init__(out self):
        self.expected_seq = 0
        self.completed_seq = 0


struct CUDARuntime(Movable):
    var _stream_id_lock: BlockingSpinLock
    var _next_stream_id: UInt64
    var _event_registry_lock: BlockingSpinLock
    var _event_registry: List[_CUDAEventState]

    fn __init__(out self):
        self._stream_id_lock = BlockingSpinLock()
        self._next_stream_id = 1
        self._event_registry_lock = BlockingSpinLock()
        self._event_registry = List[_CUDAEventState]()

    fn __moveinit__(out self, deinit take: Self):
        self._stream_id_lock = BlockingSpinLock()
        self._next_stream_id = take._next_stream_id
        self._event_registry_lock = BlockingSpinLock()
        self._event_registry = take._event_registry^

    fn _next_cuda_stream_id(mut self) -> UInt64:
        with BlockingScopedLock(self._stream_id_lock):
            var stream_id = self._next_stream_id
            self._next_stream_id += 1
            return stream_id

    fn _ensure_event_slot(mut self, mut event: CUDAEventType):
        if event.event_id != 0:
            return
        with BlockingScopedLock(self._event_registry_lock):
            if event.event_id == 0:
                self._event_registry.append(_CUDAEventState())
                event.event_id = UInt64(self._event_registry.__len__())

    fn _record_event_seq(mut self, mut event: CUDAEventType) -> UInt64:
        self._ensure_event_slot(event)
        if event.event_id == 0:
            return 0

        with BlockingScopedLock(self._event_registry_lock):
            var idx = _event_index_from_id(event.event_id)
            if idx < 0 or idx >= self._event_registry.__len__():
                return 0
            var state = self._event_registry[idx]
            state.expected_seq += 1
            var seq = state.expected_seq
            self._event_registry[idx] = state
            return seq

    fn _mark_event_completed_by_id(mut self, mut event_id: UInt64, seq: UInt64):
        if event_id == 0:
            return
        with BlockingScopedLock(self._event_registry_lock):
            var idx = _event_index_from_id(event_id)
            if idx < 0 or idx >= self._event_registry.__len__():
                return
            var state = self._event_registry[idx]
            if state.completed_seq < seq:
                state.completed_seq = seq
                self._event_registry[idx] = state

    fn _complete_recorded_event(mut self, mut event_id: UInt64, seq: UInt64):
        self._mark_event_completed_by_id(event_id, seq)

    fn _wait_for_recorded_event(mut self, event_id: UInt64):
        if event_id == 0:
            return

        while True:
            with BlockingScopedLock(self._event_registry_lock):
                var idx = _event_index_from_id(event_id)
                if idx < 0 or idx >= self._event_registry.__len__():
                    return
                var state = self._event_registry[idx]
                if state.completed_seq == state.expected_seq:
                    return

    fn cudaEventCreateWithFlags(mut self, mut event: CUDAEventType, flags: UInt32) -> cudaError_t:
        _ = flags
        event = CUDAEventType()
        self._ensure_event_slot(event)
        if event.event_id == 0:
            return cudaErrorNotReady
        _ = _ensure_real_event(event)
        return cudaSuccess

    fn cudaEventDestroy(mut self, mut event: CUDAEventType) -> cudaError_t:
        event.has_real_event = False
        event.real_event = None

        if event.event_id == 0:
            return cudaSuccess

        with BlockingScopedLock(self._event_registry_lock):
            var idx = _event_index_from_id(event.event_id)
            if idx >= 0 and idx < self._event_registry.__len__():
                self._event_registry[idx] = _CUDAEventState()
        event.event_id = 0
        return cudaSuccess

    fn cudaEventRecord(mut self, mut event: CUDAEventType, stream: CUDAStreamType) -> cudaError_t:
        var record_seq = self._record_event_seq(event)
        if event.event_id == 0 or record_seq == 0:
            return cudaErrorNotReady

        try:
            var actual_stream = _resolve_device_stream(stream)
            if _ensure_real_event(event):
                actual_stream.record_event(event.real_event.value())
        except e:
            return cudaErrorNotReady

        self._mark_event_completed_by_id(event.event_id, record_seq)
        return cudaSuccess

    fn cudaStreamWaitEvent(
        mut self, stream: CUDAStreamType, event: CUDAEventType, flags: UInt32
    ) -> cudaError_t:
        _ = flags
        if event.event_id == 0:
            return cudaSuccess

        var actual_stream = CUDAStreamType()
        try:
            actual_stream = _resolve_device_stream(stream)
        except e:
            return cudaErrorNotReady

        if event.has_real_event and event.real_event:
            try:
                actual_stream.enqueue_wait_for(event.real_event.value())
                return cudaSuccess
            except e:
                return cudaErrorNotReady

        self._wait_for_recorded_event(event.event_id)
        return cudaSuccess

    fn cudaEventQuery(mut self, read event: CUDAEventType) -> cudaError_t:
        if event.event_id == 0:
            return cudaSuccess

        with BlockingScopedLock(self._event_registry_lock):
            var idx = _event_index_from_id(event.event_id)
            if idx < 0 or idx >= self._event_registry.__len__():
                return cudaErrorNotReady
            var state = self._event_registry[idx]
            if state.completed_seq == state.expected_seq:
                return cudaSuccess
        return cudaErrorNotReady

    fn cudaEventMarkCompleted(mut self, mut event: CUDAEventType) -> cudaError_t:
        if event.event_id == 0:
            return cudaSuccess

        with BlockingScopedLock(self._event_registry_lock):
            var idx = _event_index_from_id(event.event_id)
            if idx < 0 or idx >= self._event_registry.__len__():
                return cudaErrorNotReady
            var state = self._event_registry[idx]
            state.completed_seq = state.expected_seq
            self._event_registry[idx] = state
        return cudaSuccess



@always_inline
fn _default_device_stream() raises -> CUDAStreamType:
    var ctx = DeviceContext(api="cuda")
    return CUDAStreamType(ctx.stream())


@always_inline
fn _resolve_device_stream(stream: CUDAStreamType) raises -> CUDAStreamType:
    if stream.is_default():
        return _default_device_stream()
    return stream


@always_inline
fn _event_index_from_id(event_id: UInt64) -> Int:
    return Int(event_id) - 1


fn _ensure_real_event(mut event: CUDAEventType) -> Bool:
    if event.has_real_event and event.real_event:
        return True

    try:
        var ctx = DeviceContext(api="cuda")
        event.real_event = ctx.create_event()
        event.has_real_event = True
        return True
    except e:
        event.has_real_event = False
        event.real_event = None
        return False


fn cudaGetDevice(mut device: Int) -> cudaError_t:
    try:
        var ctx = DeviceContext()
        device = Int(ctx.id())
        return cudaSuccess
    except e:
        return cudaErrorNotReady


fn cudaSetDevice(device: Int) -> cudaError_t:
    try:
        _ = DeviceContext(device_id=device)
        return cudaSuccess
    except e:
        return cudaErrorNotReady


fn cudaEventCreateWithFlags(mut event: CUDAEventType, flags: UInt32, mut runtime: CUDARuntime) -> cudaError_t:
    var result = runtime.cudaEventCreateWithFlags(event, flags)
    if result == cudaSuccess:
        event.runtime = UnsafePointer(to=runtime)
    return result


fn cudaEventDestroy(mut event: CUDAEventType) -> cudaError_t:
    if event.runtime == UnsafePointer[CUDARuntime, MutAnyOrigin]():
        return cudaSuccess
    return event.runtime[].cudaEventDestroy(event)


fn cudaEventRecord(mut event: CUDAEventType, stream: CUDAStreamType) -> cudaError_t:
    if event.runtime == UnsafePointer[CUDARuntime, MutAnyOrigin]():
        return cudaErrorNotReady
    return event.runtime[].cudaEventRecord(event, stream)


fn cudaStreamWaitEvent(
    stream: CUDAStreamType, event: CUDAEventType, flags: UInt32
) -> cudaError_t:
    if event.runtime == UnsafePointer[CUDARuntime, MutAnyOrigin]():
        return cudaSuccess
    return event.runtime[].cudaStreamWaitEvent(stream, event, flags)


fn cudaEventQuery(read event: CUDAEventType) -> cudaError_t:
    if event.runtime == UnsafePointer[CUDARuntime, MutAnyOrigin]():
        return cudaSuccess
    return event.runtime[].cudaEventQuery(event)


fn cudaEventMarkCompleted(mut event: CUDAEventType) -> cudaError_t:
    if event.runtime == UnsafePointer[CUDARuntime, MutAnyOrigin]():
        return cudaSuccess
    return event.runtime[].cudaEventMarkCompleted(event)
