from collections import Deque
from utils.lock import BlockingSpinLock, BlockingScopedLock


struct ConcurrentQueue[ElementType: Copyable & ImplicitlyDestructible](Movable):
    var _deque: Deque[Self.ElementType]
    var _lock: BlockingSpinLock

    fn __init__(out self):
        self._deque = Deque[Self.ElementType]()
        self._lock = BlockingSpinLock()

    fn __moveinit__(out self, deinit take: Self):
        self._deque = take._deque^
        self._lock = BlockingSpinLock()

    fn enqueue(mut self, var item: Self.ElementType):
        with BlockingScopedLock(self._lock):
            self._deque.append(item^)

    fn dequeue(mut self) -> Optional[Self.ElementType]:
        with BlockingScopedLock(self._lock):
            if len(self._deque) == 0:
                return None
            try:
                return self._deque.popleft()
            except:
                return None

    fn peek_front(self) -> Optional[Self.ElementType]:
        with BlockingScopedLock(self._lock):
            if len(self._deque) == 0:
                return None
            try:
                return self._deque[0]
            except:
                return None

    fn __len__(self) -> Int:
        with BlockingScopedLock(self._lock):
            return len(self._deque)
