import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Opal Link: your phone (KDE Connect app) and other Opal devices on this network.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    readonly property bool on: Hub.prefs.linkEnabled === true
    readonly property var nearby: Hub.linkDevices.filter(d => !d.paired && d.reachable)
    Component.onCompleted: if (on) Hub.link("refresh")
    ColumnLayout {
        id: column; width: parent.width; spacing: 8
        SettingToggle { Layout.fillWidth: true; icon: "devices"; title: "Opal Link"; description: "Works with the KDE Connect app and other Opal devices"; checked: page.on; onToggled: Hub.set("linkEnabled", !checked) }
        // Port taken by KDE Connect.
        Rectangle {
            visible: page.on && Hub.linkStatus === "busy"
            Layout.fillWidth: true; implicitHeight: busyColumn.implicitHeight + 28; radius: Theme.shapeLg; color: Theme.tertiaryContainer
            ColumnLayout { id: busyColumn; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14; spacing: 8
                MText { text: "KDE Connect is running"; role: "titleS"; color: Theme.onTertiaryContainer }
                MText { text: "Both use the same network port. Opal Link can take over and keep your existing pairings."; role: "bodyS"; color: Theme.onTertiaryContainer; wrapMode: Text.Wrap; Layout.fillWidth: true }
                MButton { text: "Use Opal Link instead"; filled: true; compact: true; onClicked: Hub.link("stop-kde") } }
        }
        MText { visible: page.on && Hub.linkStatus === "error"; text: Hub.linkDetail; role: "bodyS"; color: Theme.error; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.leftMargin: 6 }
        ColumnLayout {
            visible: page.on && Hub.linkStatus === "running"; Layout.fillWidth: true; spacing: 8
            RowLayout { Layout.fillWidth: true; Layout.topMargin: 8
                MText { text: "Paired"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.fillWidth: true }
                MButton { icon: "refresh"; compact: true; implicitWidth: 38; ink: Theme.subtext; tooltip: "Look for devices"; onClicked: Hub.link("refresh") }
            }
            LinkDevices { Layout.fillWidth: true }
            MText { text: "Nearby"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 12 }
            Repeater {
                model: page.nearby
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true; implicitHeight: 60; radius: Theme.shapeLg; color: Theme.level(3)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 8; spacing: 12
                        Glyph { name: modelData.type === "phone" ? "smartphone" : modelData.type === "tablet" ? "tablet" : "desktop_windows"; font.pixelSize: 22; color: Theme.primary; Layout.preferredWidth: 26 }
                        ColumnLayout { Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 0
                            MText { text: modelData.name; role: "titleS"; Layout.fillWidth: true }
                            MText { text: modelData.pairRequested ? "Wants to pair" : modelData.pairPending ? "Waiting for the other device…" : modelData.opal ? "Opal device" : "KDE Connect"; role: "labelS"; color: Theme.subtext } }
                        MButton { visible: modelData.pairRequested; text: "Accept"; filled: true; compact: true; onClicked: Hub.link("accept", modelData.id) }
                        MButton { visible: !modelData.pairRequested && !modelData.pairPending; text: "Pair"; tonal: true; compact: true; onClicked: Hub.link("pair", modelData.id) }
                    }
                }
            }
            MText { visible: page.nearby.length === 0; text: "Open KDE Connect on your phone, on the same Wi-Fi, to see it here."; role: "bodyS"; color: Theme.subtext; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.leftMargin: 6 }
            MText { text: "Options"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 12 }
            SettingToggle { Layout.fillWidth: true; first: true; last: false; icon: "content_paste"; title: "Share clipboard"; description: "Copy on one device, paste on another"; checked: Hub.prefs.linkClipboard !== false; onToggled: Hub.set("linkClipboard", !checked) }
            SettingToggle { Layout.fillWidth: true; first: false; last: true; icon: "devices"; title: "Show what I'm doing"; description: "Your Opal devices can open the same app or music"; checked: Hub.prefs.linkSession !== false; onToggled: Hub.set("linkSession", !checked) }
        }
    }
}
