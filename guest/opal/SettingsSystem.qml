import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// Updates and system health: disks and temperatures.
Flickable {
    id: page
    contentHeight: column.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}
    Component.onCompleted: { Hub.command({action: "health"}); if (Hub.updates.pacman === null) Hub.command({action: "updates"}); }
    function size(bytes) { return bytes >= 1e12 ? (bytes / 1e12).toFixed(1) + " TB" : Math.round(bytes / 1e9) + " GB"; }
    readonly property int pending: (Hub.updates.pacman || 0) + (Hub.updates.flatpak || 0)
    ColumnLayout {
        id: column; width: parent.width; spacing: 10
        Rectangle {
            Layout.fillWidth: true; implicitHeight: updateRow.implicitHeight + 32; radius: Theme.shapeXl
            color: page.pending > 0 ? Theme.primaryContainer : Theme.level(3)
            RowLayout {
                id: updateRow; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 20; spacing: 14
                Glyph { name: page.pending > 0 ? "system_update" : "verified"; font.pixelSize: 30; color: page.pending > 0 ? Theme.onContainer : Theme.primary }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    MText { text: Hub.updates.pacman === null && Hub.updates.flatpak === null ? "Checking for updates…" : page.pending > 0 ? page.pending + " updates available" : "Up to date"; role: "title"; color: page.pending > 0 ? Theme.onContainer : Theme.text }
                    MText { text: (Hub.updates.pacman !== null ? Hub.updates.pacman + " system" : "") + (Hub.updates.flatpak !== null ? " · " + Hub.updates.flatpak + " Flatpak" : ""); role: "labelS"; color: page.pending > 0 ? Theme.alpha(Theme.onContainer, .8) : Theme.subtext } }
                MButton { icon: "refresh"; compact: true; implicitWidth: 40; ink: page.pending > 0 ? Theme.onContainer : Theme.subtext; tooltip: "Check again"; onClicked: { Hub.updates = {pacman: null, flatpak: null}; Hub.command({action: "updates"}); } }
                MButton { visible: page.pending > 0; text: "Update"; filled: true; onClicked: Hub.command({action: "system-update"}) }
            }
        }
        MText { text: "Storage"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 8 }
        Repeater {
            model: Hub.health.disks
            Rectangle {
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 72; radius: Theme.shapeLg; color: Theme.level(3)
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 8
                    RowLayout { Layout.fillWidth: true
                        MText { text: modelData.label; role: "titleS"; Layout.fillWidth: true }
                        MText { text: page.size(modelData.used) + " of " + page.size(modelData.total); role: "label"; color: Theme.subtext } }
                    Rectangle { Layout.fillWidth: true; height: 8; radius: 4; color: Theme.alpha(Theme.primary, .18)
                        Rectangle { width: parent.width * modelData.percent / 100; height: 8; radius: 4; color: modelData.percent >= 90 ? Theme.error : Theme.primary } }
                }
            }
        }
        MText { text: "Temperatures"; role: "label"; color: Theme.primary; Layout.leftMargin: 6; Layout.topMargin: 8 }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: Object.keys(Hub.health.temperatures || {})
                Rectangle {
                    required property string modelData
                    readonly property int value: Hub.health.temperatures[modelData]
                    width: 150; height: 64; radius: Theme.shapeLg; color: value >= 85 ? Theme.mix(Theme.level(3), Theme.error, .2) : Theme.level(3)
                    Column { anchors.centerIn: parent; spacing: 2
                        MText { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.value + "°C"; role: "title"; font.features: {"tnum": 1} }
                        MText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData; role: "labelS"; color: Theme.subtext } }
                }
            }
        }
        MText { text: "Opal warns you when a disk is nearly full or the machine runs hot."; role: "labelS"; color: Theme.subtext; Layout.leftMargin: 6; Layout.topMargin: 8 }
    }
}
