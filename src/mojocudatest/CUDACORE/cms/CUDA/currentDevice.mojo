from CUDACompat import cudaGetDevice
from cudaCheck import cudaCheck_


fn currentDevice() raises -> Int:
    var dev: Int = -1
    _ = cudaCheck_(
        "currentDevice.mojo", 0,
        "cudaGetDevice",
        cudaGetDevice(dev),
    )
    return dev
