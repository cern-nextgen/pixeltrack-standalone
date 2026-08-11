struct OrderedMultiSet[T: Copyable & ImplicitlyCopyable, Compare: AnyType](Movable, Sized):
    # Sorted storage using a comparator type with `less(a, b) -> Bool`.
    var _items: List[Self.T]

    @always_inline
    fn __init__(out self):
        self._items = List[Self.T]()

    fn __moveinit__(out self, deinit take: Self):
        self._items = take._items^

    @always_inline
    fn __len__(self) -> Int:
        return self._items.__len__()

    @always_inline
    fn is_empty(self) -> Bool:
        return self._items.__len__() == 0

    @always_inline
    fn clear(ref self):
        self._items.clear()

    @always_inline
    fn __getitem__(self, index: Int) raises -> Self.T:
        return self._items[index]

    @always_inline
    fn _less(self, read a: Self.T, read b: Self.T) -> Bool:
        return Compare.less(a, b)

    @always_inline
    fn _equivalent(self, read a: Self.T, read b: Self.T) -> Bool:
        return (not self._less(a, b)) and (not self._less(b, a))

    # Returns the first position where `value` can be inserted without
    # violating sorted order.
    fn lower_bound(self, read value: Self.T) -> Int:
        var i: Int = 0
        var n = self._items.__len__()
        while i < n:
            if not self._less(self._items[i], value):
                return i
            i += 1
        return n

    # Returns one matching index or -1 if no equivalent element exists.
    fn find(self, read value: Self.T) -> Int:
        var i = self.lower_bound(value)
        if i < self._items.__len__() and self._equivalent(self._items[i], value):
            return i
        return -1

    fn insert(mut self, value: Self.T):
        # Append and shift left to keep ordering by comparator.
        self._items.append(value)
        var i = self._items.__len__() - 1
        while i > 0 and self._less(self._items[i], self._items[i - 1]):
            var tmp = self._items[i - 1]
            self._items[i - 1] = self._items[i]
            self._items[i] = tmp
            i -= 1

    fn erase_at(mut self, index: Int) -> Bool:
        if index < 0 or index >= self._items.__len__():
            return False
        try:
            _ = self._items.pop(index)
        except:
            pass
        return True

    fn erase_one(mut self, read value: Self.T) -> Bool:
        var index = self.find(value)
        if index == -1:
            return False
        try:
            _ = self._items.pop(index)
        except:
            pass
        return True
