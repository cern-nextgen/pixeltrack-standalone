from pathlib import Path

from MojoSerial.Framework.EventSetup import EventSetup
from MojoSerial.MojoBridge.DTypes import Typeable

trait ESProducer(Copyable, Defaultable, Movable, Typeable):
    fn __init__(out self, var path: Path):
        ...

    fn produce(mut self, mut eventSetup: EventSetup):
        ...
