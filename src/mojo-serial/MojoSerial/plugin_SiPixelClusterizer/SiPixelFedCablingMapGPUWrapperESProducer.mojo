from pathlib import Path

from MojoSerial.CondFormats.SiPixelFedIds import SiPixelFedIds
from MojoSerial.CondFormats.SiPixelFedCablingMapGPU import (
    SiPixelFedCablingMapGPU,
)
from MojoSerial.CondFormats.SiPixelFedCablingMapGPUWrapper import (
    SiPixelFedCablingMapGPUWrapper,
)
from MojoSerial.Framework.ESProducer import ESProducer
from MojoSerial.Framework.EventSetup import EventSetup
from MojoSerial.MojoBridge.DTypes import UChar, Typeable
from MojoSerial.MojoBridge.File import (
    read_simd,
    read_obj,
    read_list,
)


@fieldwise_init
struct SiPixelFedCablingMapGPUWrapperESProducer(ESProducer):
    var _data: Path

    @always_inline
    fn __init__(out self):
        self._data = Path("")

    fn produce(mut self, mut eventSetup: EventSetup):
        try:
            with open(self._data / "fedIds.bin", "r") as file:
                var nfeds = read_simd[DType.uint32](file)
                var fedIds = read_list[UInt32](file, Int(nfeds))
                eventSetup.put[SiPixelFedIds](SiPixelFedIds(fedIds^))
            with open(self._data / "cablingMap.bin", "r") as file:
                var obj = read_obj[SiPixelFedCablingMapGPU](file)
                var modToUnpDefSize = read_simd[DType.uint32](file)
                var modToUnpDefault: List[UChar] = file.read_bytes(
                    Int(modToUnpDefSize)
                )
                eventSetup.put[SiPixelFedCablingMapGPUWrapper](
                    SiPixelFedCablingMapGPUWrapper(obj^, modToUnpDefault^)
                )
        except e:
            print(
                (
                    "Error during loading data in"
                    " SiPixelFedCablingMapGPUWrapperESProducer:"
                ),
                e,
            )

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "SiPixelFedCablingMapGPUWrapperESProducer"
