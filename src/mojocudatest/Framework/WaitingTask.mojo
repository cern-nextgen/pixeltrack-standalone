from Framework.TaskBase import TaskBase
from os.atomic import Atomic, Consistency

struct WaitingTask(TaskBase):
    var expected : Atomic[DType.int32](0)
    var ErrorMsg : String

    fn __init__(out self):
        pass

    #Sorry for the naming this returns a pointer
    #The naming is as such to be consistent with the cpp WaitingTask 
    fn exceptionPtr(self) -> String:
        return ErrorMsg

    
    fn _dependentTaskFailed(ErrorMsg : String):
        if(expected.compare_exchange(0 , 1)):
            self.ErrorMsg = ErrorMsg
      



    
struct FinalWaitingTask(WaitingTask):
    var FinalTask : TaskBase
    var m_done : Atomic[bool](false)

    fn __init__(out self, FinalTask : TaskBase):
        self.FinalTask = FinalTask

    fn execute(self):
        m_done.store(true)
    
    fn done(self) -> bool:
        return m_done.load()

trait Executable:
    def execute(self): ...

struct FunctorWaitingTask[F : Executable](WaitingTask):
    var Func : F

    fn __init__(out self, Func : F):
        self.Func = Func^

    # Mojo doesnt have an exception pointer so if you want an error to be returned it has to be
    # within a mechanism of your own design, such as a callback or a shared variable.
    fn execute(self):
        self.Func.execute()
    
def make_Waiting_Task[F : Executable](Func : F) -> FunctorWaitingTask[F]:
    return FunctorWaitingTask(Func)
