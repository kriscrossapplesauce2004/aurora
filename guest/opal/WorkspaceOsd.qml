import QtQuick
import Quickshell
import Quickshell.Wayland
// Workspace indicator: slides down from the top edge on a workspace switch, then slides away.
PanelWindow {
    id: osd
    // The target is computed once; reading the window screen back would make a binding loop with visible.
    readonly property var target: Hub.chooseScreen()
    screen: target
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
    implicitWidth: pill.width + 24
    implicitHeight: 72
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "opal-toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    // Desktop bars show the workspace in the clock pill instead.
    readonly property bool inBar: !!target && Hub.layoutFor(target.width, target.height, target.name) === "desktop" && (Hub.status.fullscreenMonitors || []).indexOf(target.name) < 0
    visible: pill.y > -pill.height && !inBar
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
    WorkspacePill { id: pill; anchors.horizontalCenter: parent.horizontalCenter; shown: osd.shown; out: osd.out }
}
