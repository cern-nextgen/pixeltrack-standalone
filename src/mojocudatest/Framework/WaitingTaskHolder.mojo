from Framework.WaitingTask import WaitingTask
from runtime.asyncrt import TaskGroup


# Port of Framework/WaitingTaskHolder.h through C++ line 54.
# C++ uses tbb::task_group* and WaitingTask*.
alias TaskGroupPtr = UnsafePointer[TaskGroup]
alias WaitingTaskPtr = UnsafePointer[WaitingTask]


struct WaitingTaskHolder(Movable):
    var m_task: WaitingTaskPtr
    var m_group: TaskGroupPtr

    fn __init__(out self):
        self.m_task = WaitingTaskPtr()
        self.m_group = TaskGroupPtr()

    fn __init__(out self, ref group: TaskGroup, task: WaitingTaskPtr):
        self.m_task = task
        self.m_group = UnsafePointer(to=group)
        self.m_task[].increment_ref_count()

    fn __del__(owned self):
        if self.m_task != WaitingTaskPtr():
            self.doneWaiting("")

    fn __copyinit__(out self, other: Self):
        self.m_task = other.m_task
        self.m_group = other.m_group
        self.m_task[].increment_ref_count()

    fn __moveinit__(out self, var other: Self):
        self.m_task = other.m_task
        self.m_group = other.m_group
        other.m_task = WaitingTaskPtr()

    fn taskHasFailed(self) -> Bool:
        return self.m_task[].exceptionPtr() != ""
    
    fn hasTask(self) -> Bool:
        return self.m_task != WaitingTaskPtr()

    fn group(self) -> TaskGroupPtr:
        return self.m_group

    fn presetTaskAsFailed(mut self, iExcept: String):
        if iExcept != "":
            self.m_task[]._dependentTaskFailed(iExcept)
    async fn execute(m_task: WaitingTaskPtr):
        m_task[].execute()
        
    async fn doneWaiting(mut self, iExcept: String):
        if iExcept != "":
            self.m_task[]._dependentTaskFailed(iExcept)
        #  task_group::run can run the task before we finish
        #  doneWaiting and some other thread might
        #  try to reuse this object. Resetting
        #  before spawn avoids problems
        var task = self.m_task
        self.m_task = WaitingTaskPtr()
        m_group[].create_task(execute(task))
        await m_group[]
            
        
    fn _release_no_decrement(mut self) -> WaitingTaskPtr:
        var task = self.m_task
        self.m_task = WaitingTaskPtr()
        return task
