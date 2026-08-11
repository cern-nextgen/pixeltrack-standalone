from collections import Deque
from sys.terminate import exit

from Framework.Event import Event
from Framework.EventSetup import EventSetup
from Framework.ProductRegistry import ProductRegistry
from Framework.PluginFactory import PluginFactory, EDProducerConcrete
from MojoBridge.DTypes import Typeable
from Bin.Source import Source
from CUDAAppContext import CUDAAppContext


struct StreamSchedule(Defaultable, Movable, Typeable):
    var _registry: UnsafePointer[ProductRegistry, MutAnyOrigin]
    var _source: UnsafePointer[Source, MutAnyOrigin]
    var _eventSetup: UnsafePointer[EventSetup, MutAnyOrigin]
    var _path: List[EDProducerConcrete]
    var _streamId: Int32
    var _cuda_ctx: UnsafePointer[CUDAAppContext, MutAnyOrigin]

    @always_inline
    fn __init__(out self):
        self._registry = UnsafePointer[ProductRegistry, MutAnyOrigin]()
        self._source = UnsafePointer[Source, MutAnyOrigin]()
        self._eventSetup = UnsafePointer[EventSetup, MutAnyOrigin]()
        self._path = []
        self._streamId = 0
        self._cuda_ctx = UnsafePointer[CUDAAppContext, MutAnyOrigin]()

    fn __init__(
        out self,
        reg: UnsafePointer[ProductRegistry, MutAnyOrigin],
        source: UnsafePointer[Source, MutAnyOrigin],
        eventSetup: UnsafePointer[EventSetup, MutAnyOrigin],
        edreg: UnsafePointer[Framework.PluginFactory.Registry, MutAnyOrigin],
        streamId: Int32 = 0,
    ):
        try:
            self._registry = reg
            self._source = source
            self._eventSetup = eventSetup
            self._streamId = streamId
            self._cuda_ctx = alloc[CUDAAppContext](1)
            __get_address_as_uninit_lvalue(self._cuda_ctx.address) = CUDAAppContext()

            var nModules = PluginFactory.size(edreg[])
            debug_assert(nModules > 0)

            var producers = List[EDProducerConcrete](capacity=nModules)
            var adj = List[List[Int]](length=nModules, fill=[])
            var in_degree = List[Int](length=nModules, fill=0)

            var i: Int = 0
            for name in PluginFactory.getAll(edreg[]):
                self._registry[].beginModuleConstruction(Int32(i + 1))
                producers.append(
                    PluginFactory.create(name, self._registry[], edreg[])
                )
                # remove dependency on FEDRawDataCollection from resolver logic
                # it is the parent of all producers (guaranteed by Source)
                var count = 0
                for dep_index in self._registry[].consumedModules():
                    if dep_index == UInt(0):
                        continue
                    adj[Int(dep_index) - 1].append(i)
                    count += 1
                in_degree[i] = count
                i += 1

            var q = Deque[Int]()
            for i in range(nModules):
                if in_degree[i] == 0:
                    q.append(i)

            var sorted_indices = List[Int](capacity=nModules)
            while q.__len__() > 0:
                var u = q.pop()
                sorted_indices.append(u)

                for v in adj[u]:
                    in_degree[v] -= 1
                    if in_degree[v] == 0:
                        q.append(v)

            if sorted_indices.__len__() != nModules:
                raise Error(
                    "A cycle was detected in the module dependency graph."
                )

            self._path = List[EDProducerConcrete](capacity=nModules)
            var data = producers.steal_data()
            for index in sorted_indices:
                self._path.append((data + index).take_pointee())
        except e:
            print("Error occurred in Bin/StreamSchedule.mojo,", e)
            if self._cuda_ctx != UnsafePointer[CUDAAppContext, MutAnyOrigin]():
                self._cuda_ctx.destroy_pointee()
                self._cuda_ctx.free()
                self._cuda_ctx = UnsafePointer[CUDAAppContext, MutAnyOrigin]()
            return Self()

    fn __del__(var self):
        if self._cuda_ctx != UnsafePointer[CUDAAppContext, MutAnyOrigin]():
            self._cuda_ctx.destroy_pointee()
            self._cuda_ctx.free()

    @always_inline
    fn __moveinit__(out self, deinit take: Self):
        self._registry = take._registry
        self._source = take._source
        self._eventSetup = take._eventSetup
        self._path = take._path^
        self._streamId = take._streamId
        self._cuda_ctx = take._cuda_ctx

    fn run(mut self):
        var ptr = self._source[].produce(self._streamId, self._registry[])
        while ptr != UnsafePointer[Event, MutAnyOrigin]():
            for i in range(self._path.__len__()):
                self._path[i].produce(ptr[], self._eventSetup[])
            if self._source[].maxEvents() >= 0 and self._source[].processedEvents() >= self._source[].maxEvents():
                exit(0)
            ptr = self._source[].produce(self._streamId, self._registry[])

    fn endJob(mut self):
        for i in range(self._path.__len__()):
            self._path[i].endJob()

    @always_inline
    @staticmethod
    fn dtype() -> String:
        return "StreamSchedule"
