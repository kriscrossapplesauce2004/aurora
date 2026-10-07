import QtQuick
// Passive pointer watcher: it tells PhoneState when a pen is in use. It never takes events from other items.
Item {
    PointHandler {
        acceptedDevices: PointerDevice.Stylus
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) PhoneState.penSeen()
    }
    PointHandler {
        acceptedDevices: PointerDevice.TouchScreen
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) PhoneState.touchSeen()
    }
}
