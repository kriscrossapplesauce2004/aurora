import QtQuick
import Quickshell
import Quickshell.Wayland
// Workspace indicator: slides down from the top edge on a workspace switch, then slides away.
PanelWindow {
    id: osd
    screen: Hub.chooseScreen()
    property int shown: 0
    property int baseline: -1
    property bool out: false
    readonly property var numbers: {
        const known = (Hub.status.workspaces || []).filter(n => n > 0);
        const top = Math.max(3, Math.min(10, Math.max.apply(null, known.concat([osd.shown || 1]))));
        return Array.from({length: top}, (_, i) => i + 1);
    }
    readonly property int activeIndex: Math.max(0, numbers.indexOf(shown))
    function count(n) { return Hub.windows.filter(w => w.workspace === n).length; }
    anchors { top: true }
    margins.top: 0
    implicitWidth: numbers.length * 34 + 24
    implicitHeight: 72
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "opal-toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: pill.y > -pill.height
    mask: Region {}
    // The first value after startup is only a baseline, so login and reload stay quiet.
    Connections {
        target: Hub
        function onStatusChanged() {
            const w = Hub.status.workspace || 0;
            if (!Hub.status.hypr || w <= 0) return;
            if (osd.baseline < 0) { osd.baseline = w; osd.shown = w; return; }
            if (w === osd.shown && osd.out) { hide.restart(); return; }
            if (w === osd.shown) return;
            osd.shown = w;
            osd.out = true;
            hide.restart();
        }
    }
    Timer { id: hide; interval: 1300; onTriggered: osd.out = false }
    Island {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 12; height: 44
        y: osd.out ? 14 : -height - 4
        Behavior on y { NumberAnimation { duration: Theme.motion(osd.out ? 420 : 260); easing.type: osd.out ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.1 } }
        Rectangle {
            x: 6 + osd.activeIndex * 34 + 2; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 10
            color: Theme.light ? Theme.containerInk : Theme.primary
            Behavior on x { NumberAnimation { duration: Theme.motion(360); easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }
        Row {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: osd.numbers
                Item {
                    id: slot
                    required property int modelData
                    required property int index
                    readonly property bool current: index === osd.activeIndex
                    readonly property int windows: osd.count(modelData)
                    width: 34; height: 34
                    MText {
                        anchors.centerIn: parent; anchors.verticalCenterOffset: slot.windows > 0 ? -2 : 0
                        text: slot.modelData; font.pixelSize: 13; font.weight: slot.current ? Font.Bold : Font.Medium
                        color: slot.current ? (Theme.light ? Theme.primaryContainer : Theme.onPrimary) : slot.windows > 0 ? Theme.text : Theme.alpha(Theme.text, .4)
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; spacing: 2
                        Repeater { model: Math.min(3, slot.windows); Rectangle { width: 3; height: 3; radius: 1.5; color: slot.current ? (Theme.light ? Theme.primaryContainer : Theme.onPrimary) : Theme.text; opacity: slot.current ? 1 : .55 } }
                    }
                }
            }
        }
    }
}
