import QtQuick
import Quickshell
import Quickshell.Wayland
// Draggable divider between the two windows of a split view. The handle is large enough for a pen or a finger.
Scope {
    PanelWindow {
        id: divider
        readonly property var target: PhoneState.splitScreen
        screen: target || Quickshell.screens[0]
        visible: PhoneState.splitActive && target !== null
        readonly property real areaWidth: target ? target.width : 0
        readonly property real handleWidth: PhoneState.pen ? 40 : 32
        anchors { top: true; bottom: true; left: true }
        margins.top: PhoneState.barHeight
        margins.bottom: PhoneState.navFor(target)
        // The window sits over the gap and follows the ratio while dragging.
        property real frozen: -1
        margins.left: frozen >= 0 ? frozen : Math.round((areaWidth - 8) * PhoneState.splitRatio + 4 - handleWidth / 2)
        implicitWidth: handleWidth
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "opal-split"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        // The gap between the two windows, the full height, with the grip on it.
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 8; height: parent.height; color: Theme.base }
        Rectangle {
            id: grip
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - width) / 2 + (area.pressed ? (PhoneState.splitRatio - area.startRatio) * (divider.areaWidth - 8) : 0)
            width: area.pressed ? 10 : 6; height: area.pressed ? 96 : 72; radius: width / 2
            color: area.pressed ? Theme.primary : Theme.alpha(Theme.text, .7)
            Behavior on width { NumberAnimation { duration: Theme.motion(120) } }
            Behavior on height { NumberAnimation { duration: Theme.motion(160); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.motion(120) } }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            preventStealing: true
            property real startRatio: .5
            property real startX: 0
            // The window stays still during a drag so pointer positions stay stable.
            onPressed: e => { startRatio = PhoneState.splitRatio; startX = e.x; divider.frozen = divider.margins.left; }
            onPositionChanged: e => { if (pressed) PhoneState.setRatio(startRatio + (e.x - startX) / Math.max(1, divider.areaWidth - 8), false); }
            onReleased: { PhoneState.setRatio(PhoneState.splitRatio, true); divider.frozen = -1; }
            onCanceled: divider.frozen = -1
            onDoubleClicked: PhoneState.setRatio(.5, true)
        }
    }
}
