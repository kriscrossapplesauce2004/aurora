import QtQuick
import Quickshell
// The tablet dock tray: pinned apps, running apps and the split view button.
Item {
    id: dock
    property var screenObj: null
    // Flat: drawn inside the navigation bar, with no floating tray of its own.
    property bool flat: false
    implicitWidth: tray.width
    implicitHeight: flat ? 60 : 72
    width: implicitWidth
    height: implicitHeight
    readonly property var pinned: Hub.favoriteApps.slice(0, 8)
    // Running apps that are not pinned, one per app.
    readonly property var running: {
        const seen = {};
        pinned.forEach(a => seen[a.id] = true);
        const list = [];
        Hub.windows.forEach(w => { const app = Hub.appForWindow(w); if (app && !seen[app.id]) { seen[app.id] = true; list.push(app); } });
        return list.slice(0, 6);
    }
    Rectangle {
        id: tray
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: dock.flat ? 60 : 72; width: row.implicitWidth + (dock.flat ? 0 : 24); radius: height / 2
        color: dock.flat ? "transparent" : Theme.alpha(Theme.dockTint, Math.max(.7, Hub.prefs.glass))
        border.width: dock.flat ? 0 : 1; border.color: Theme.outline
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Repeater {
                model: dock.pinned
                DockIcon { required property var modelData; app: modelData }
            }
            Rectangle { visible: dock.running.length > 0; width: 2; height: 36; radius: 1; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: dock.running
                DockIcon { required property var modelData; app: modelData }
            }
            Rectangle { width: 2; height: 36; radius: 1; color: Theme.outline; anchors.verticalCenter: parent.verticalCenter }
            // Split view: puts the open app and the one before it side by side.
            MButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: PhoneState.splitActive ? "close_fullscreen" : "splitscreen_vertical_add"
                tonal: PhoneState.splitActive
                contained: !PhoneState.splitActive
                implicitWidth: PhoneState.hit + 8; implicitHeight: PhoneState.hit + 8
                enabled: PhoneState.splitActive || (Hub.status.hypr && Hub.windows.length > 1)
                tooltip: PhoneState.splitActive ? "End split view" : "Split view"
                onClicked: PhoneState.splitActive ? PhoneState.endSplit() : PhoneState.splitWithPrevious(dock.screenObj)
            }
        }
    }
    component DockIcon: Item {
        id: icon
        property var app: null
        readonly property var windows: Hub.windows.filter(w => Hub.appForWindow(w) === icon.app)
        width: PhoneState.hit + 8; height: dock.flat ? 60 : 64
        OpalMenu {
            id: menu; title: icon.app ? icon.app.name : ""; icon: "apps"
            entries: {
                if (!icon.app) return [];
                const extra = [];
                const w = icon.windows[0];
                if (w && Hub.status.hypr) {
                    const active = PhoneState.activeWindow();
                    if (active && active.address !== w.address) {
                        extra.push({text: "Open beside current app", icon: "splitscreen_vertical_add", run: () => PhoneState.startSplit(dock.screenObj, active.address, w.address)});
                    }
                    extra.push({text: "Slide over", icon: "picture_in_picture", run: () => PhoneState.slideOver(dock.screenObj, w.address)});
                }
                return extra.concat(Hub.appMenu(icon.app));
            }
        }
        Rectangle { anchors.centerIn: parent; width: parent.width - 4; height: width; radius: width * .32; color: Theme.stateLayer; opacity: tap.pressed ? .14 : 0 }
        AppIcon { anchors.centerIn: parent; width: PhoneState.hit - 4; height: width; app: icon.app }
        Rectangle {
            visible: icon.windows.length > 0
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 0
            width: icon.windows.some(w => Hub.active(w)) ? 16 : 5; height: 5; radius: 2.5; color: Theme.primary
            Behavior on width { NumberAnimation { duration: Theme.motion(160); easing.type: Easing.OutCubic } }
        }
        TapHandler { id: tap; onTapped: Hub.launch(icon.app); onLongPressed: menu.popup(icon.width / 2, 0) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: menu.popup(icon.width / 2, 0) }
        Accessible.role: Accessible.Button
        Accessible.name: icon.app ? icon.app.name : ""
    }
}
