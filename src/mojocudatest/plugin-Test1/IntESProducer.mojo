from pathlib import Path

from Framework.ESProducer import ESProducer
from Framework.EventSetup import EventSetup
from MojoBridge.DTypes import Typeable, TypeableInt


struct IntESProducer(Defaultable, ESProducer, Movable, Typeable):
    # ESProducer cannot have null size in memory
    var x: Int

    @always_inline
    fn __init__(out self):
        self.x = 0

    @always_inline
    fn __init__(out self, var path: Path):
        self.x = 0

    @always_inline
    fn __moveinit__(out self, var take: Self):
        self.x = take.x

    fn produce(mut self, mut eventSetup: EventSetup):
        try:
            eventSetup.put[TypeableInt](TypeableInt(42))
        except e:
            print("Error in IntESProducer.produce,", e)

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "IntESProducer"
