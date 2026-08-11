from Framework.Event import StreamID
from deviceCount import deviceCount


fn chooseDevice(id: StreamID) -> Int:
    var count = deviceCount()
    if count <= 0:
        return 0
    return Int(id) % count
