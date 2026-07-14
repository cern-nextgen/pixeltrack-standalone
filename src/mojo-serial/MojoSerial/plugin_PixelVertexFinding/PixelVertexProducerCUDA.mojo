from MojoSerial.CUDADataFormats.ZVertexSoA import ZVertexSoA
from MojoSerial.Framework.EDGetToken import EDGetTokenT
from MojoSerial.Framework.EDProducer import EDProducer
from MojoSerial.Framework.EDPutToken import EDPutTokenT
from MojoSerial.Framework.Event import Event
from MojoSerial.Framework.EventSetup import EventSetup
from MojoSerial.Framework.ProductRegistry import ProductRegistry
from MojoSerial.MojoBridge.DTypes import Float, Typeable
from MojoSerial.plugin_PixelVertexFinding.gpuVertexFinder import Producer, TkSoA


struct PixelVertexProducerCUDA(Defaultable, EDProducer, Typeable):
    var _tokenCPUTrack: EDGetTokenT[TkSoA]
    var _tokenCPUVertex: EDPutTokenT[ZVertexSoA]

    var _gpuAlgo: Producer

    # Tracking cuts before sending tracks to vertex algo
    var _ptMin: Float

    @always_inline
    fn __init__(out self):
        self._tokenCPUTrack = EDGetTokenT[TkSoA]()
        self._tokenCPUVertex = EDPutTokenT[ZVertexSoA]()
        self._gpuAlgo = Producer(
            True,  # oneKernel
            True,  # useDensity
            False,  # useDBSCAN
            False,  # useIterative
            2,  # minT
            0.07,  # eps
            0.01,  # errmax
            9.0,  # chi2max
        )
        self._ptMin = 0.5  # 0.5 GeV

    @always_inline
    fn __init__(out self, mut reg: ProductRegistry):
        try:
            self._tokenCPUTrack = reg.consumes[TkSoA]()
            self._tokenCPUVertex = reg.produces[ZVertexSoA]()

            self._gpuAlgo = Producer(
                True,  # oneKernel
                True,  # useDensity
                False,  # useDBSCAN
                False,  # useIterative
                2,  # minT
                0.07,  # eps
                0.01,  # errmax
                9.0,  # chi2max
            )
            self._ptMin = 0.5  # 0.5 GeV
        except e:
            print("Handled exception in PixelVertexProducerCUDA, ", e)
            return Self()

    fn produce(mut self, mut iEvent: Event, ref iSetup: EventSetup):
        try:
            ref tracks = iEvent.get[TkSoA](self._tokenCPUTrack)
            debug_assert(Bool(UnsafePointer(to=tracks)))

            var vertices = self._gpuAlgo.make(
                UnsafePointer(to=tracks), self._ptMin
            )
            iEvent.put[ZVertexSoA](self._tokenCPUVertex, vertices^.take())
        except e:
            print("Error during produce in PixelVertexProducerCUDA, ", e)

    fn endJob(mut self) raises:
        pass

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "PixelVertexProducerCUDA"
