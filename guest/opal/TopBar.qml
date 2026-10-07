import QtQuick
import Quickshell
import Quickshell.Wayland
// Top status bar for the split bar style. The bottom shelf keeps Start and apps.
PanelWindow {
    id:top
    readonly property bool fullscreen:screen&&(Hub.status.fullscreenMonitors||[]).indexOf(screen.name)>=0
    visible:!fullscreen
    anchors {top:true;left:true;right:true}
    implicitHeight:56
    exclusiveZone:implicitHeight
    color:"transparent"
    WlrLayershell.namespace:"opal-shelf"
    WlrLayershell.layer:WlrLayer.Overlay
    mask:Region {item:shelf.rightIsland}
    DesktopShelf {
        id:shelf
        anchors.fill:parent
        part:"top";output:top.screen;panel:top;panelHeight:top.height
    }
}
