from time import perf_counter_ns
from pathlib import Path

from DataFormats.FEDRawDataCollection import FEDRawDataCollection
from DataFormats.DigiClusterCount import DigiClusterCount
from DataFormats.TrackCount import TrackCount
from DataFormats.VertexCount import VertexCount
from Framework.Event import Event
from Framework.ProductRegistry import ProductRegistry
from Framework.EDPutToken import EDPutTokenT
from MojoBridge.DTypes import Typeable
from MojoBridge.File import read_simd, read_simd_eof


fn readRaw(mut file: FileHandle, nfeds: UInt32) raises -> FEDRawDataCollection:
    var rawCollection = FEDRawDataCollection()
    for _ in range(nfeds):
        var fedId = read_simd[DType.uint32](file)
        var fedSize = read_simd[DType.uint32](file)
        rawCollection.FEDData(Int(fedId))._data = file.read_bytes(Int(fedSize))
    return rawCollection^


struct Source(Defaultable, Movable, Typeable):
    var _maxEvents: Int32

    var _runForMinutes: Int32
    var _startTime: UInt
    # don't need a mutex
    var _numEventsTimeLastCheck: Int32
    var _shouldStop: Bool

    var _numEvents: Int32
    var _rawToken: EDPutTokenT[FEDRawDataCollection]
    var _digiClusterToken: EDPutTokenT[DigiClusterCount]
    var _trackToken: EDPutTokenT[TrackCount]
    var _vertexToken: EDPutTokenT[VertexCount]
    var _raw: List[FEDRawDataCollection]
    var _digiclusters: List[DigiClusterCount]
    var _tracks: List[TrackCount]
    var _vertices: List[VertexCount]
    var _validation: Bool

    @always_inline
    fn __init__(out self):
        self._maxEvents = 0

        self._runForMinutes = 0
        self._startTime = 0
        self._numEventsTimeLastCheck = 0
        self._shouldStop = False

        self._numEvents = 0
        self._rawToken = EDPutTokenT[FEDRawDataCollection]()
        self._digiClusterToken = EDPutTokenT[DigiClusterCount]()
        self._trackToken = EDPutTokenT[TrackCount]()
        self._vertexToken = EDPutTokenT[VertexCount]()
        self._raw = []
        self._digiclusters = []
        self._tracks = []
        self._vertices = []
        self._validation = False

    fn __init__(
        out self,
        var maxEvents: Int32,
        var runForMinutes: Int32,
        mut reg: ProductRegistry,
        var path: Path,
        var validation: Bool,
    ):
        try:
            self._maxEvents = maxEvents

            self._runForMinutes = runForMinutes
            self._startTime = 0
            self._numEventsTimeLastCheck = 0
            self._shouldStop = False

            self._numEvents = 0
            self._rawToken = reg.produces[FEDRawDataCollection]()
            self._validation = validation
            self._raw = []
            self._digiclusters = []
            self._tracks = []
            self._vertices = []

            if self._validation:
                self._digiClusterToken = reg.produces[DigiClusterCount]()
                self._trackToken = reg.produces[TrackCount]()
                self._vertexToken = reg.produces[VertexCount]()
            else:
                self._digiClusterToken = EDPutTokenT[DigiClusterCount]()
                self._trackToken = EDPutTokenT[TrackCount]()
                self._vertexToken = EDPutTokenT[VertexCount]()

            var in_digiclusters = FileHandle()
            var in_tracks = FileHandle()
            var in_vertices = FileHandle()

            with open(path / "raw.bin", "r") as in_raw:
                if self._validation:
                    in_digiclusters = open(path / "digicluster.bin", "r")
                    in_tracks = open(path / "tracks.bin", "r")
                    in_vertices = open(path / "vertices.bin", "r")

                var nfeds = read_simd[DType.uint32](in_raw)
                while True:
                    self._raw.append(readRaw(in_raw, nfeds))
                    if self._validation:
                        var nm = read_simd[DType.uint32](in_digiclusters)
                        var nd = read_simd[DType.uint32](in_digiclusters)
                        var nc = read_simd[DType.uint32](in_digiclusters)
                        var nt = read_simd[DType.uint32](in_tracks)
                        var nv = read_simd[DType.uint32](in_vertices)
                        self._digiclusters.append(DigiClusterCount(nm, nd, nc))
                        self._tracks.append(TrackCount(nt))
                        self._vertices.append(VertexCount(nv))
                    var eofEvent = read_simd_eof[DType.uint32](in_raw)
                    if eofEvent[0]:
                        break
                    else:
                        nfeds = eofEvent[1]

                if self._validation:
                    in_digiclusters.close()
                    in_tracks.close()
                    in_vertices.close()

            if self._validation:
                debug_assert(
                    self._raw.__len__() == self._digiclusters.__len__()
                )
                debug_assert(self._raw.__len__() == self._tracks.__len__())
                debug_assert(self._raw.__len__() == self._vertices.__len__())

            if self._runForMinutes < 0 and self._maxEvents < 0:
                self._maxEvents = self._raw.__len__()
        except e:
            print("Error occurred in Bin/Source.mojo,", e)
            return Self()

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._maxEvents = take._maxEvents

        self._runForMinutes = take._runForMinutes
        self._startTime = take._startTime
        self._numEventsTimeLastCheck = take._numEventsTimeLastCheck
        self._shouldStop = take._shouldStop

        self._numEvents = take._numEvents
        self._rawToken = take._rawToken
        self._digiClusterToken = take._digiClusterToken
        self._trackToken = take._trackToken
        self._vertexToken = take._vertexToken
        self._validation = take._validation
        self._raw = take._raw^
        self._digiclusters = take._digiclusters^
        self._tracks = take._tracks^
        self._vertices = take._vertices^


    @always_inline
    fn reconfigure(mut self, var maxEvents: Int32, var runForMinutes: Int32):
        self._maxEvents = maxEvents
        self._runForMinutes = runForMinutes
        self._numEventsTimeLastCheck = 0
        self._shouldStop = False
        self._numEvents = 0

    @always_inline
    fn startProcessing(mut self):
        if self._runForMinutes >= 0:
            self._startTime = perf_counter_ns()

    @always_inline
    fn maxEvents(self) -> Int32:
        return self._maxEvents

    @always_inline
    fn processedEvents(self) -> Int32:
        return self._numEvents

    fn produce(
        mut self, streamId: Int32, ref reg: ProductRegistry
    ) -> UnsafePointer[Event, MutAnyOrigin]:
        """
        Returns a HEAP-ALLOCATED event. Deallocate memory after using.
        Note: When Mojo supports this, it would be optimal to revamp this function with an Optional[OwnedPointer[Event]] return value.
        """
        var res = UnsafePointer[Event, MutAnyOrigin]()
        if self._shouldStop:
            return res
        var old = self._numEvents
        self._numEvents += 1
        var iev = old + 1
        if self._runForMinutes < 0:
            if old >= self._maxEvents:
                self._shouldStop = True
                self._numEvents -= 1
                return res
        else:
            if (
                self._numEvents - self._numEventsTimeLastCheck
                > self._raw.__len__()
            ):
                # this is in nanoseconds
                var processingTime: UInt = perf_counter_ns() - self._startTime
                if (processingTime // (6 * 10**10)) >= UInt(
                    self._runForMinutes
                ):
                    self._shouldStop = True
                self._numEventsTimeLastCheck = (
                    self._numEvents // self._raw.__len__()
                ) * self._raw.__len__()
            if self._shouldStop:
                self._numEvents -= 1
                return res

        var ev = Event(Int(streamId), Int(self._numEvents), reg)
        var index = (self._numEvents - 1) % self._raw.__len__()

        ev.put[FEDRawDataCollection](self._rawToken, self._raw[index])
        if self._validation:
            ev.put[DigiClusterCount](
                self._digiClusterToken, self._digiclusters[index]
            )
            ev.put[TrackCount](self._trackToken, self._tracks[index])
            ev.put[VertexCount](self._vertexToken, self._vertices[index])
        res = alloc[Event](1)
        __get_address_as_uninit_lvalue(res.address) = ev^
        return res

    @staticmethod
    @always_inline
    fn dtype() -> String:
        return "Source"
