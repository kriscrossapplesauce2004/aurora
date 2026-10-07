import QtQuick
import Quickshell
import Quickshell.Wayland
// Persistent tablet dock: pinned apps, a divider, then running apps, and split view. Every target is a tap target, never hover.
Scope {
    Variants {
        model: Quickshell.screens.filter(sc => PhoneState.isTablet(sc) && Hub.prefs.tabletDock !== false)
        delegate: PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            anchors { bottom: true; left: true; right: true }
            // Fixed place above the navigation bar. The navigation bar reserves this room, so the stacking does not depend on map order.
            exclusionMode: ExclusionMode.Ignore
            margins.bottom: PhoneState.navHeight
            implicitHeight: 84
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "opal-tablet-dock"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region { item: tray }
            PenWatcher { anchors.fill: parent }
            TabletDockTray { id: tray; anchors.centerIn: parent; screenObj: dockWindow.modelData }
        }
    }
}
