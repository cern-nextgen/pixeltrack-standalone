from CUDACompat import cudaGetDevice, cudaSetDevice
from cudaCheck import cudaCheck_


struct ScopedSetDevice:
    var prevDevice_: Int

    fn __init__(out self, newDevice: Int) raises:
        _ = cudaCheck_(
            __source_location().file_name(),
            __source_location().line(),
            "cudaGetDevice",
            cudaGetDevice(self.prevDevice_),
        )
        _ = cudaCheck_(
            __source_location().file_name(),
            __source_location().line(),
            "cudaSetDevice",
            cudaSetDevice(newDevice),
        )
        var currentDevice: Int = -1
        _ = cudaCheck_(
            __source_location().file_name(),
            __source_location().line(),
            "cudaGetDevice",
            cudaGetDevice(currentDevice),
        )
        if currentDevice != newDevice:
            raise (
                "RuntimeError: ScopedSetDevice failed to select device "
                + String(newDevice)
                + " (current device is "
                + String(currentDevice)
                + ")"
            )

    fn __del__(var self):
        # Intentionally don't check the return value to avoid
        # exceptions to be thrown. If this call fails, the process is
        # doomed anyway.
        _ = cudaSetDevice(self.prevDevice_)
