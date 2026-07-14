from sys import is_defined

from MojoSerial.CUDACore.VecArray import VecArray
from MojoSerial.CUDACore.SimpleVector import SimpleVector
from MojoSerial.CUDACore.HistoContainer import OneToManyAssoc
from MojoSerial.CUDADataFormats.GPUClusteringConstants import (
    GPUClusteringConstants,
)
from MojoSerial.MojoBridge.DTypes import DType


@parameter
fn maxNumberOfTuples() -> UInt32:
    if is_defined["ONLY_PHICUT"]():
        return 48 * 1024
    if is_defined["GPU_SMALL_EVENTS"]():
        return 3 * 1024
    return 24 * 1024


@parameter
fn maxNumberOfQuadruplets() -> UInt32:
    return maxNumberOfTuples()


@parameter
fn maxNumberOfDoublets() -> UInt32:
    if is_defined["ONLY_PHICUT"]():
        return 2 * 1024 * 1024
    if is_defined["GPU_SMALL_EVENTS"]():
        return 128 * 1024
    return 512 * 1024


@parameter
fn maxCellsPerHit() -> UInt32:
    if is_defined["ONLY_PHICUT"]():
        return 8 * 128
    if is_defined["GPU_SMALL_EVENTS"]():
        return 128 // 2
    return 128


@parameter
fn maxNumOfActiveDoublets() -> UInt32:
    return maxNumberOfDoublets() // 8


@parameter
fn maxNumberOfLayerPairs() -> UInt32:
    return 20


@parameter
fn maxNumberOfLayers() -> UInt32:
    return 10


@parameter
fn maxTuples() -> UInt32:
    return maxNumberOfTuples()


alias _MaxCellsPerHit: Int = Int(maxCellsPerHit())

alias _MaxNumberOfTuples: UInt32 = maxNumberOfTuples()

alias _CellNeighborsCapacity: Int = (
    36 if not is_defined["ONLY_PHICUT"]() else 64
)

alias _CellTracksCapacity: Int = 48 if not is_defined["ONLY_PHICUT"]() else 64

alias hindex_type = UInt16
alias tindex_type = UInt16


alias CellNeighbors = VecArray[UInt32, "CellNeighbors", _CellNeighborsCapacity]
alias CellTracks = VecArray[tindex_type, "CellTracks", _CellTracksCapacity]

alias CellNeighborsVector = SimpleVector[CellNeighbors, "CellNeighborsVector"]
alias CellTracksVector = SimpleVector[CellTracks, "CellTracksVector"]

alias OuterHitOfCell = VecArray[UInt32, "OuterHitOfCell", _MaxCellsPerHit]
alias TuplesContainer = OneToManyAssoc[
    DType.uint16, _MaxNumberOfTuples, 5 * _MaxNumberOfTuples
]
alias HitToTuple = OneToManyAssoc[
    DType.uint16, GPUClusteringConstants.maxNumberOfHits, 4 * _MaxNumberOfTuples
]
alias TupleMultiplicity = OneToManyAssoc[
    DType.uint16, 8, _MaxNumberOfTuples
]
