import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// The phone while docked: trackpad and control panel pages you swipe between, a way back to the
// phone's own screen, and a screen-dark mode that wakes on touch.
Scope {
    PanelWindow {
        id: window
        screen: Hub.phoneScreen || Quickshell.screens[0]
        visible: Hub.docked && Hub.phoneScreen !== null && (Hub.phoneDockMode !== "screen" || Hub.phoneDark)
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "opal-phone-dock"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: Hub.phoneDark ? "#000000" : Theme.base
        PhoneDockPanel { anchors.fill: parent; visible: !Hub.phoneDark }
        MouseArea { anchors.fill: parent; visible: Hub.phoneDark; onClicked: Hub.phoneDark = false }
    }
    // In second-screen mode a small pill brings the docked controls back.
    PanelWindow {
        screen: Hub.phoneScreen || Quickshell.screens[0]
        visible: Hub.docked && Hub.phoneScreen !== null && Hub.phoneDockMode === "screen" && !Hub.phoneDark
        anchors { top: true }
        margins.top: 56
        implicitWidth: pill.width; implicitHeight: 40
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "opal-toast"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        Rectangle {
            id: pill; height: 40; width: pillRow.implicitWidth + 28; radius: 20; color: Theme.primaryContainer
            Row { id: pillRow; anchors.centerIn: parent; spacing: 8
                Glyph { name: "cast_connected"; font.pixelSize: 18; color: Theme.onContainer; anchors.verticalCenter: parent.verticalCenter }
                MText { text: "Docked · controls"; role: "label"; color: Theme.onContainer; anchors.verticalCenter: parent.verticalCenter } }
            MouseArea { anchors.fill: parent; onClicked: Hub.setPhoneDockMode("trackpad") }
        }
    }
}
