from pathlib import Path

from Framework.EventSetup import EventSetup


trait ESProducer(Defaultable):
    fn __init__(out self, var path: Path):
        ...

    fn produce(mut self, mut eventSetup: EventSetup):
        ...
