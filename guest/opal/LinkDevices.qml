import QtQuick
import QtQuick.Layouts
import Quickshell
// Paired Opal Link devices: battery, and what an Opal device is doing so you can continue here.
ColumnLayout {
    id: list
    property bool compact: false
    readonly property var devices: Hub.linkDevices.filter(d => d.paired)
    spacing: 6
    function glyph(type) { return type === "phone" ? "smartphone" : type === "tablet" ? "tablet" : type === "laptop" ? "laptop" : "desktop_windows"; }
    Repeater {
        model: list.devices
        Rectangle {
            id: card
            required property var modelData
            readonly property var session: modelData.session || {}
            readonly property var app: Hub.appForClass(session.app)
            Layout.fillWidth: true
            implicitHeight: cardColumn.implicitHeight + 24
            radius: Theme.shapeLg; color: Theme.level(3)
            opacity: modelData.reachable ? 1 : .6
            ColumnLayout {
                id: cardColumn; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; anchors.leftMargin: 16; spacing: 8
                RowLayout { Layout.fillWidth: true; spacing: 12
                    Glyph { name: list.glyph(card.modelData.type); font.pixelSize: 22; color: Theme.primary; Layout.preferredWidth: 26 }
                    ColumnLayout { Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 0
                        MText { text: card.modelData.name; role: "titleS"; Layout.fillWidth: true }
                        MText { text: !card.modelData.reachable ? "Not nearby" : card.modelData.battery >= 0 ? card.modelData.battery + "%" + (card.modelData.charging ? " · charging" : "") : "Connected"; role: "labelS"; color: Theme.subtext } }
                    MButton { visible: !list.compact && card.modelData.reachable; icon: "notifications_active"; compact: true; implicitWidth: 38; ink: Theme.subtext; tooltip: "Ring"; onClicked: Hub.link("ring", card.modelData.id) }
                    MButton { visible: card.modelData.reachable; icon: "content_paste_go"; compact: true; implicitWidth: 38; ink: Theme.subtext; tooltip: "Send clipboard"; onClicked: { Hub.link("clipboard", card.modelData.id); Hub.message("Sent to " + card.modelData.name); } }
                    MButton { visible: !list.compact; icon: "link_off"; compact: true; implicitWidth: 38; ink: Theme.subtext; tooltip: "Unpair"; onClicked: Hub.link("unpair", card.modelData.id) }
                }
                // Continuity from another Opal device.
                Rectangle {
                    visible: card.modelData.opal && card.modelData.reachable && (card.app !== null || card.session.track)
                    Layout.fillWidth: true; implicitHeight: 44; radius: 22; color: Theme.secondaryContainer
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 6; spacing: 8
                        Glyph { name: card.app ? "open_in_new" : "music_note"; font.pixelSize: 18; color: Theme.onSecondaryContainer }
                        MText { text: card.app ? "Using " + card.app.name : "Playing " + card.session.track; role: "label"; color: Theme.onSecondaryContainer; Layout.fillWidth: true }
                        MButton { visible: card.app !== null; text: "Open here"; compact: true; implicitHeight: 32; filled: true; onClicked: Hub.launch(card.app) }
                    }
                }
            }
        }
    }
    MText { visible: list.devices.length === 0; text: Hub.linkStatus === "running" ? "No paired devices yet" : "Turn on Opal Link in Settings"; role: "bodyS"; color: Theme.subtext; Layout.leftMargin: 6 }
}
