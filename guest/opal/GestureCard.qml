import QtQuick
import Quickshell
// A window card for gestures: a live preview when the compositor allows it, else the app icon and title.
Rectangle {
    id: card
    property var entry: null
    readonly property var app: entry ? Hub.appForWindow(entry) : null
    color: Theme.level(2)
    clip: true
    border.width: 1
    border.color: Theme.outline
    Loader {
        anchors.fill: parent
        active: !!card.entry && Hub.status.hypr && !!card.entry.address && card.width > 0
        source: "HyprWindowPreview.qml"
        onLoaded: item.address = Qt.binding(() => card.entry.address || "")
    }
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: !card.entry || !Hub.status.hypr
        Glyph { anchors.horizontalCenter: parent.horizontalCenter; visible: icon.status !== Image.Ready; name: "apps"; font.pixelSize: 56; color: Theme.primary }
        Image {
            id: icon
            visible: status === Image.Ready
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; sourceSize: Qt.size(144, 144)
            source: Quickshell.iconPath(card.app ? card.app.icon : "application-x-executable", true)
        }
        MText { anchors.horizontalCenter: parent.horizontalCenter; text: card.entry ? card.entry.title : "Home"; role: "title"; elide: Text.ElideRight; width: Math.min(card.width - 32, implicitWidth) }
    }
}
