from sys import argv
from sys.terminate import exit
from time import perf_counter_ns
from pathlib import Path

from Bin.EventProcessor import EventProcessor
from Bin.PosixClockGettime import (
    PosixClockGettime,
    CLOCK_PROCESS_CPUTIME_ID,
)
from Framework.ESPluginFactory import Registry as ESRegistry, fwkEventSetupModule
from Framework.PluginFactory import Registry as EDRegistry, fwkModule
from IntESProducer import IntESProducer
from TestProducer import TestProducer


fn print_help(name: String):
    print(
        "Usage:",
        name,
        "[--warmupEvents WE] [--maxEvents ME] [--runForMinutes RM]",
        "[--data PATH] [--empty]",
    )


fn main() raises:
    var args = argv()
    var warmupEvents = 0
    var maxEvents = -1
    var runForMinutes = -1
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
        elif args[i] == "--data":
            i += 1
            path = Path(args[i])
        elif args[i] == "--empty":
            empty = True
        else:
            print("Invalid parameter", args[i])
            exit(1)
        i += 1

    if maxEvents >= 0 and runForMinutes >= 0:
        print("Got both --maxEvents and --runForMinutes, please give only one")
        exit(1)

    if not path:
        path = Path("data")

    if not path.exists():
        print("Data directory '", path, "' does not exist", sep="")
        exit(1)

    var _esreg = ESRegistry()
    var _edreg = EDRegistry()
    if not empty:
        fwkEventSetupModule[IntESProducer](_esreg)
        fwkModule[TestProducer](_edreg)

    var processor = EventProcessor(
        warmupEvents,
        maxEvents,
        runForMinutes,
        path,
        False,
        UnsafePointer(to=_esreg),
        UnsafePointer(to=_edreg),
    )

    if runForMinutes < 0:
        print("Processing", processor.maxEvents(), "events", end="")
    else:
        print("Processing for about", runForMinutes, "minutes", end="")
    if warmupEvents > 0:
        print(" after", warmupEvents, "events of warm up", end="")
    print(", with 1 concurrent event and 1 thread.")

    processor.warmUp()
    var cpu_start = PosixClockGettime[CLOCK_PROCESS_CPUTIME_ID].now()
    var start = perf_counter_ns()
    processor.runToCompletion()
    var cpu_stop = PosixClockGettime[CLOCK_PROCESS_CPUTIME_ID].now()
    var stop = perf_counter_ns()
    processor.endJob()

    _ = _esreg^
    _ = _edreg^

    var diff = stop - start
    var time = Float64(diff) / 1e9
    var cpu_diff = cpu_stop - cpu_start
    var cpu = Float64(cpu_diff) / 1e9
    var nevents = Int(processor.processedEvents())

    print(
        "Processed", nevents, "events in", time, "seconds, throughput",
        nevents / time, "events/s, CPU usage:",
        round(cpu / time * 100), "%",
    )
    exit(0)
