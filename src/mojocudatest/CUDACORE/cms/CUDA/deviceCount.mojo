from std.gpu.host import DeviceContext

fn deviceCount() -> Int:
    try:
        return DeviceContext.number_of_devices(api="cuda")
    except e:
        return 0
