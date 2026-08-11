from algorithm import parallelize
from Framework.WaitingTaskHolder import (
    TaskGroupPtr,
    WaitingTaskHolder,
    WaitingTaskPtr,
)
from Framework.WaitingTask import WaitingTask
from runtime.asyncrt import TaskGroup


async fn _executeWaitingTask(task: WaitingTaskPtr):
    task[].execute()


struct TaskArena(Movable):
    var _enqueue_workers: Int

    fn __init__(out self):
        self._enqueue_workers = 1

    @staticmethod
    fn attach() -> Self:
        return Self()

    fn __copyinit__(out self, other: Self):
        self._enqueue_workers = other._enqueue_workers

    fn __moveinit__(out self, var other: Self):
        self._enqueue_workers = other._enqueue_workers

    fn enqueue(self, group: TaskGroupPtr, task: WaitingTaskPtr):
        @parameter
        fn enqueue_deferred_task(i: Int):
            _ = i
            group[].create_task(_executeWaitingTask(task))

        parallelize[enqueue_deferred_task](1, self._enqueue_workers)


# Mojo does not expose the TBB task_arena/task_handle pair used by the C++
# class. TaskArena records the enqueue point and bounces the final scheduling
# step through parallelize so doneWaiting() can be called from outside the code
# path that originally created the holder.
struct WaitingTaskWithArenaHolder(Movable):
    var m_task: WaitingTaskPtr
    var m_group: TaskGroupPtr
    var m_arena: TaskArena

    fn __init__(out self):
        self.m_task = WaitingTaskPtr()
        self.m_group = TaskGroupPtr()
        self.m_arena = TaskArena.attach()

    fn __init__(out self, ref group: TaskGroup, task: WaitingTaskPtr):
        self.m_task = task
        self.m_group = UnsafePointer(to=group)
        self.m_arena = TaskArena.attach()
        if self.m_task != WaitingTaskPtr():
            self.m_task[].increment_ref_count()

    fn __init__(out self, var holder: WaitingTaskHolder):
        self.m_task = holder._release_no_decrement()
        self.m_group = holder.group()
        self.m_arena = TaskArena.attach()

    fn __del__(owned self):
        if self.m_task != WaitingTaskPtr():
            self.doneWaiting("")

    fn __copyinit__(out self, other: Self):
        self.m_task = other.m_task
        self.m_group = other.m_group
        self.m_arena = other.m_arena
        if self.m_task != WaitingTaskPtr():
            self.m_task[].increment_ref_count()

    fn __moveinit__(out self, var other: Self):
        self.m_task = other.m_task
        self.m_group = other.m_group
        self.m_arena = other.m_arena^
        other.m_task = WaitingTaskPtr()
        other.m_group = TaskGroupPtr()

    fn doneWaiting(mut self, iExcept: String):
        if self.m_task == WaitingTaskPtr():
            return

        if iExcept != "":
            self.m_task[]._dependentTaskFailed(iExcept)

        # create_task can run the task before doneWaiting returns. Clear the
        # holder first so another thread cannot reuse this object with stale
        # task state.
        var task = self.m_task
        self.m_task = WaitingTaskPtr()

        if task[].decrement_ref_count() == 0:
            self.m_arena.enqueue(self.m_group, task)

    fn makeWaitingTaskHolderAndRelease(mut self) -> WaitingTaskHolder:
        var holder = WaitingTaskHolder(self.m_group[], self.m_task)
        _ = self.m_task[].decrement_ref_count()
        self.m_task = WaitingTaskPtr()
        return holder^

    fn taskHasFailed(self) -> Bool:
        if self.m_task == WaitingTaskPtr():
            return False
        return self.m_task[].exceptionPtr() != ""

    fn hasTask(self) -> Bool:
        return self.m_task != WaitingTaskPtr()

    fn group(self) -> TaskGroupPtr:
        return self.m_group


trait WaitingTaskWithHolderExecutable:
    def execute(mut self, var holder: WaitingTaskWithArenaHolder):
        ...


struct LambdaWithHolder[F: WaitingTaskWithHolderExecutable & Movable](Movable):
    var holder: WaitingTaskWithArenaHolder
    var func: F

    fn __init__(out self, var holder: WaitingTaskWithArenaHolder, var func: F):
        self.holder = holder^
        self.func = func^

    fn execute(mut self):
        try:
            self.func.execute(self.holder)
        except e:
            self.holder.doneWaiting("exception in make_lambda_with_holder")


fn make_lambda_with_holder[
    F: WaitingTaskWithHolderExecutable & Movable
](var holder: WaitingTaskWithArenaHolder, var func: F) -> LambdaWithHolder[F]:
    return LambdaWithHolder[F](holder^, func^)


struct WaitingTaskWithHolderTask[
    F: WaitingTaskWithHolderExecutable & Movable
](WaitingTask):
    var holder: WaitingTaskWithArenaHolder
    var func: LambdaWithHolder[F]

    fn __init__(
        out self, var holder: WaitingTaskWithArenaHolder, var func: LambdaWithHolder[F]
    ):
        self.holder = holder^
        self.func = func^

    fn execute(mut self):
        var exception = self.exceptionPtr()
        if exception != "":
            self.holder.doneWaiting(exception)
            return

        self.func.execute()


fn make_waiting_task_with_holder[
    F: WaitingTaskWithHolderExecutable & Movable
](var holder: WaitingTaskWithArenaHolder, var func: F) -> WaitingTaskWithHolderTask[F]:
    var lambda_holder = holder
    var lambda = make_lambda_with_holder(lambda_holder^, func^)
    return WaitingTaskWithHolderTask[F](holder^, lambda^)
