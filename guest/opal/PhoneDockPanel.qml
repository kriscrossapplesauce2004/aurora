import QtQuick
import QtQuick.Layouts
import Quickshell

// Docked phone pages: Trackpad and Control panel. Swipe sideways; "Phone" returns to the phone's own home.
Item {
    id: panel
    readonly property var modes: ["trackpad", "panel"]
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; anchors.topMargin: 56; anchors.bottomMargin: 20; spacing: 12
        // Mode switcher.
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: [{id: "trackpad", label: "Trackpad", icon: "touchpad_mouse"}, {id: "panel", label: "Controls", icon: "dashboard"}, {id: "screen", label: "Phone", icon: "smartphone"}]
                Rectangle {
                    required property var modelData
                    readonly property bool current: Hub.phoneDockMode === modelData.id
                    Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 22
                    color: current ? Theme.secondaryContainer : Theme.level(2)
                    Row { anchors.centerIn: parent; spacing: 6
                        Glyph { name: parent.parent.modelData.icon; font.pixelSize: 18; color: parent.parent.current ? Theme.onSecondaryContainer : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                        MText { text: parent.parent.modelData.label; role: "label"; color: parent.parent.current ? Theme.onSecondaryContainer : Theme.text; anchors.verticalCenter: parent.verticalCenter } }
                    MouseArea { anchors.fill: parent; onClicked: Hub.setPhoneDockMode(parent.modelData.id) }
                }
            }
            MButton { icon: "dark_mode"; compact: true; implicitWidth: 44; implicitHeight: 44; contained: true; tooltip: "Screen dark"; onClicked: Hub.phoneDark = true }
        }
        ListView {
            id: pages
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: ListView.Horizontal; snapMode: ListView.SnapOneItem; highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: Theme.motion(Theme.durMedium); boundsBehavior: Flickable.StopAtBounds; clip: true
            interactive: false
            model: panel.modes
            currentIndex: Math.max(0, panel.modes.indexOf(Hub.phoneDockMode))
            delegate: Loader {
                required property string modelData
                width: pages.width; height: pages.height
                sourceComponent: modelData === "trackpad" ? trackpad : controls
            }
        }
    }
    Component { id: trackpad; DockTrackpad {} }
    Component {
        id: controls
        Flickable {
            contentHeight: controlColumn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: controlColumn; width: parent.width; spacing: 12
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 88; radius: Theme.shapeXl; color: Theme.primaryContainer
                    RowLayout { anchors.fill: parent; anchors.margins: 18; spacing: 14
                        Glyph { name: "cast_connected"; font.pixelSize: 30; color: Theme.onContainer }
                        ColumnLayout { Layout.fillWidth: true; spacing: 0
                            MText { text: "Docked to " + Hub.dockOutput; role: "title"; color: Theme.onContainer }
                            MText { text: Hub.sessionModes[Hub.dockOutput] === "console" ? "Play" : "Desktop"; role: "label"; color: Theme.alpha(Theme.onContainer, .8) } }
                        MButton { text: Hub.sessionModes[Hub.dockOutput] === "console" ? "Desktop" : "Play"; compact: true; tonal: true
                            onClicked: { const m = Object.assign({}, Hub.sessionModes); m[Hub.dockOutput] = m[Hub.dockOutput] === "console" ? "desktop" : "console"; Hub.sessionModes = m; } }
                    }
                }
                MediaCard { Layout.fillWidth: true; visible: Hub.status.track !== ""; compact: true }
                MText { text: "Apps on the big screen"; role: "label"; color: Theme.primary; Layout.leftMargin: 6 }
                Repeater {
                    model: Hub.windows.filter(w => w.monitor === Hub.dockOutput)
                    Rectangle {
                        required property var modelData
                        readonly property var app: Hub.appForWindow(modelData)
                        Layout.fillWidth: true; implicitHeight: 60; radius: Theme.shapeLg; color: Theme.level(3)
                        RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 6; spacing: 12
                            AppIcon { Layout.preferredWidth: 36; Layout.preferredHeight: 36; app: parent.parent.app }
                            MText { text: parent.parent.modelData.title; role: "body"; Layout.fillWidth: true }
                            MButton { text: "Bring here"; compact: true; onClicked: { const phone = (Hub.status.monitors || []).find(m => Hub.phoneScreen && m.name === Hub.phoneScreen.name); if (phone) Hub.command({action: "move-window", address: parent.parent.modelData.address, number: phone.workspace, follow: true}); } }
                        }
                    }
                }
                MText { visible: !Hub.windows.some(w => w.monitor === Hub.dockOutput); text: "Nothing open there yet"; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6 }
                RowLayout { Layout.fillWidth: true; spacing: 8
                    MButton { Layout.fillWidth: true; text: "Keyboard"; icon: "keyboard"; tonal: true; onClicked: Hub.systemOsk("show") }
                    MButton { Layout.fillWidth: true; text: "Notifications" + (Hub.unread ? " · " + Hub.unread : ""); icon: "notifications"; tonal: true; onClicked: { Hub.targetScreen = Hub.phoneScreen; Hub.page = "notifications"; } }
                }
            }
        }
    }
}
