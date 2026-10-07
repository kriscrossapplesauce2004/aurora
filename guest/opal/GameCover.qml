import QtQuick
import QtQuick.Effects
import Quickshell
// Portrait cover for a game or app. Without art it draws a tonal cover with the title.
Item {
    id: cover
    property var entry: null
    property bool selected: false
    property bool running: false
    signal activated()
    readonly property string art: entry ? entry.cover || "" : ""
    readonly property int tint: entry ? Math.abs(entry.title.split("").reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7)) % 3 : 0
    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: cover.selected ? 0 : 6
        radius: Theme.shapeLg
        clip: true
        color: [Theme.primaryContainer, Theme.secondaryContainer, Theme.tertiaryContainer][cover.tint]
        Behavior on anchors.margins { NumberAnimation { duration: Theme.motion(Theme.durShort); easing.type: Easing.OutCubic } }
        Image {
            id: image
            anchors.fill: parent
            source: cover.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(400, 600)
            // GPU rendering masks the art to the card shape; software rendering shows it square.
            readonly property bool ready: status === Image.Ready
            visible: ready && GraphicsInfo.api === GraphicsInfo.Software
        }
        Rectangle { id: coverMask; visible: false; width: card.width; height: card.height; radius: card.radius; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            visible: image.ready && GraphicsInfo.api !== GraphicsInfo.Software
            source: image
            maskEnabled: true; maskSource: coverMask
            maskThresholdMin: .5; maskSpreadAtMin: 1; autoPaddingEnabled: false
        }
        // Generated cover: icon and title.
        Column {
            visible: !image.ready
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 16
            spacing: 10
            Image {
                width: 48; height: 48
                source: cover.entry && cover.entry.icon ? (cover.entry.icon.startsWith("file:") ? cover.entry.icon : Quickshell.iconPath(cover.entry.icon, true)) : ""
                sourceSize: Qt.size(96, 96); visible: status === Image.Ready; asynchronous: true
            }
            MText {
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 4
                text: cover.entry ? cover.entry.title : ""
                role: "title"; font.pixelSize: Math.max(16, Math.min(24, cover.width / 8))
                color: [Theme.onContainer, Theme.onSecondaryContainer, Theme.onTertiaryContainer][cover.tint]
            }
            MText {
                text: cover.entry ? (cover.entry.source || "App").toUpperCase() : ""
                role: "labelS"; font.letterSpacing: 1.5
                color: Theme.alpha([Theme.onContainer, Theme.onSecondaryContainer, Theme.onTertiaryContainer][cover.tint], .7)
            }
        }
        // Running badge.
        Rectangle {
            visible: cover.running
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 10
            width: runningLabel.implicitWidth + 20; height: 26; radius: 13
            color: Theme.primary
            MText { id: runningLabel; anchors.centerIn: parent; text: "Running"; role: "labelS"; font.weight: Font.Bold; color: Theme.onPrimary }
        }
    }
    // Focus ring.
    Rectangle {
        anchors.fill: card; anchors.margins: -4
        radius: card.radius + 4
        color: "transparent"
        border.width: 3; border.color: Theme.primary
        visible: cover.selected
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cover.activated() }
    Accessible.role: Accessible.Button
    Accessible.name: entry ? entry.title : ""
}
