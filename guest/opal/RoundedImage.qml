import QtQuick
import QtQuick.Effects

// Image with rounded corners. Software rendering shows it square, like GameCover.
Item {
    id: art
    property url source
    property real radius: Theme.shapeLg
    property int fillMode: Image.PreserveAspectCrop
    property size decodeSize: Qt.size(640, 360)
    readonly property bool ready: image.status === Image.Ready
    Image {
        id: image
        anchors.fill: parent
        source: art.source
        fillMode: art.fillMode
        asynchronous: true
        sourceSize: art.decodeSize
        visible: art.ready && GraphicsInfo.api === GraphicsInfo.Software
    }
    Rectangle { id: mask; visible: false; width: art.width; height: art.height; radius: art.radius; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        visible: art.ready && GraphicsInfo.api !== GraphicsInfo.Software
        source: image
        maskEnabled: true; maskSource: mask
        maskThresholdMin: .5; maskSpreadAtMin: 1; autoPaddingEnabled: false
    }
}
