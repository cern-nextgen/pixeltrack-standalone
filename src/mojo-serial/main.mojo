from sys import argv
from sys.terminate import exit
from time import perf_counter_ns
from pathlib import Path

from MojoSerial.Bin.EventProcessor import EventProcessor
from MojoSerial.Bin.PosixClockGettime import (
    PosixClockGettime,
    CLOCK_THREAD_CPUTIME_ID,
)
from MojoSerial.MojoBridge.DTypes import Double
from algorithm.functional import parallelize


fn print_help(ref name: String):
    print(
        "Usage:",
        name,
        "[--warmupEvents WE] [--maxEvents ME] [--runForMinutes RM]",
        "[--threads N] [--data PATH] [--validation] [--histogram] [--empty]",
    )
    print(
        r"""(
Options:
  --warmupEvents                Number of events to process before starting the benchmark (default 0).
  --maxEvents                   Number of events to process (default -1 for all events in the input file).
  --runForMinutes               Continue processing the set of 1000 events until this many minutes have passed
                                (default -1 for disabled; conflicts with --maxEvents).
  --data                        Path to the 'data' directory (default 'data' in the directory of the executable).
  --empty                       Ignore all producers (for testing only).
  --threads                     Number of streams/threads to run concurrently (default 1).
)"""
    )


fn main() raises:
    var args = argv()
    var warmupEvents = 0
    var maxEvents = -1
    var runForMinutes = -1
    var threads = 1
    var path = Path("")
    var empty = False

    var i = 1
    while i < args.__len__():
        if args[i] == "-h" or args[i] == "--help":
            print_help(args[0])
            exit(0)
        elif args[i] == "--warmupEvents":
            i += 1
            warmupEvents = Int(args[i])
        elif args[i] == "--maxEvents":
            i += 1
            maxEvents = Int(args[i])
        elif args[i] == "--runForMinutes":
            i += 1
            runForMinutes = Int(args[i])
        elif args[i] == "--threads":
            i += 1
            threads = Int(args[i])
        elif args[i] == "--data":
            i += 1
            path = Path(args[i])
        elif args[i] == "--empty":
            empty = True
        else:
            print("Invalid parameter", args[i])
            print()
            exit(1)
        i += 1

    if maxEvents >= 0 and runForMinutes >= 0:
        print(
            "Got both --maxEvents and --runForMinutes, please give only one of"
            " them"
        )
        exit(1)
    if threads <= 0:
        print("Invalid --threads value, must be >= 1")
        exit(1)

    if not path:
        path = Path("data")

    if not path.exists():
        print("Data directory '", path, "' does not exist", sep="")
        exit(1)

    if runForMinutes < 0:
        print("Processing", maxEvents, "events", end="")
    else:
        print("Processing for about", runForMinutes, "minutes", end="")
    if warmupEvents > 0:
        print(" after", warmupEvents, "events of warm up", end="")
    print(", with ", threads, " concurrent events and ", threads, " threads.", sep="")


    var startEvent = List[Int](length=threads, fill=0)
    var endEvent = List[Int](length=threads, fill=0)

    if maxEvents > 0:
        var base = maxEvents // threads
        var rem = maxEvents % threads

        var offset = 0
        for t in range(threads):
            var count = base + (1 if t < rem else 0)
            startEvent[t] = offset
            endEvent[t] = offset + count
            offset += count
    else:
        for t in range(threads):
            startEvent[t] = 0
            endEvent[t] = -1

    var start = List[UInt](length=threads, fill=0)
    var end = List[UInt](length=threads, fill=0)

    var processed = List[Int](length=threads, fill=0)

    var cpu_start = List[UInt](length=threads, fill=0)
    var cpu_end = List[UInt](length=threads, fill=0)

    fn worker(i : Int) capturing:
        ## Init plugins manually
        var _esreg = MojoSerial.Framework.ESPluginFactory.Registry()
        var _edreg = MojoSerial.Framework.PluginFactory.Registry()
        if not empty:
            MojoSerial.PluginSiPixelClusterizer.init(_esreg, _edreg)
            MojoSerial.PluginBeamSpotProducer.init(_esreg, _edreg)
            MojoSerial.PluginSiPixelRecHits.init(_esreg, _edreg)

        var processor = EventProcessor(
            warmupEvents,
            startEvent[i],
            endEvent[i],
            runForMinutes,
            path,
            False,
            _esreg,
            _edreg,
        )

        processor.warmUp()
        start[i] = perf_counter_ns()
        cpu_start[i] = PosixClockGettime[CLOCK_THREAD_CPUTIME_ID].now()
        processor.runToCompletion()
        end[i] = perf_counter_ns()
        cpu_end[i] = PosixClockGettime[CLOCK_THREAD_CPUTIME_ID].now()
        processor.endJob()

        # Lifetime registry extension
        _ = _esreg^
        _ = _edreg^

        processed[i] = Int(processor.processedEvents())

    parallelize[worker](threads, threads)

    var begin = start[0]
    var stop = end[0]
    for i in range(threads):
        begin = min(begin, start[i])
        stop = max(stop, end[i])

    # Work done, report timing
    var diff = stop - begin
    # in seconds
    var time: Double = diff / (10**9)

    var cpu_begin = cpu_start[0]/threads
    var cpu_stop = cpu_end[0]/threads
    for i in range(1, threads):
        cpu_begin = cpu_begin + cpu_start[i]/threads
        cpu_stop = cpu_stop + cpu_end[i]/threads

    var cpu_diff = cpu_stop - cpu_begin
    var cpu: Double = cpu_diff / (10**9)

    var totalEvents = 0
    for i in range(threads):
        totalEvents += processed[i]

    print(
        "Processed ",
        totalEvents,
        " events in ",
        time,
        " seconds, throughput ",
        (totalEvents / time),
        " events/s, CPU usage: ",
        round(cpu / time * 100),
        "%",
        sep="",
    )
