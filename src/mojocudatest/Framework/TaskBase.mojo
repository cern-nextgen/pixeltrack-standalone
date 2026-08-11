from builtin.dtype import DType
from os.atomic import Atomic


# Port of Framework/TaskBase.h
#
# Base type for framework tasks. In C++ this is an abstract base class with
# virtual execute()/recycle() and atomic reference counting.
struct TaskBase(Movable,ImplicitlyDestructible):
    var m_refCount: Atomic[DType.uint32]

    fn __init__(out self):
        self.m_refCount = Atomic[DType.uint32](0)

    fn __moveinit__(out self, var other: Self):
        # Atomic is not movable; preserve the counter value.
        self.m_refCount = Atomic[DType.uint32](other.m_refCount.load())

    # Override in concrete task implementations.
    fn execute(mut self):
        pass

    fn increment_ref_count(mut self):
        _ = self.m_refCount.fetch_add(1)

    fn decrement_ref_count(mut self) -> UInt32:
        return self.m_refCount.fetch_sub(1) - 1

    # C++ default is `delete this;`.
    # In Mojo, lifetime is managed by the owning pointer/container.
    fn recycle(mut self):
        pass


# RAII helper that calls recycle() when it goes out of scope.
# this struct is useless you need to delete the task using the owning pointer/container
struct TaskSentry:
    #NOTE DO NOT USE THIS STRUCT, it is not useful and does not actually manage the lifetime of the task, you need to delete the task using the owning pointer/container
    var m_task: UnsafePointer[TaskBase]

    fn __init__(out self, task: UnsafePointer[TaskBase]):
        self.m_task = task


    fn __del__(mut self):
        if self.m_task != UnsafePointer[TaskBase]():
            self.m_task[].recycle()
