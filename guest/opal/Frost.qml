import QtQuick
import QtQuick.Effects
// Frosted glass for cards that share the wallpaper surface. The compositor cannot blur content inside one surface, so this blurs the wallpaper image region behind the card.
Item {
    id: frost
    property Item backdrop: null
    property real radius: 28
    property bool strong: false
    property real tint: strong ? .80 : Math.max(.42, Math.min(.82, Hub.prefs.glass + .06))
    property color fill: strong ? Theme.glassRaised : Theme.glassIsland
    readonly property bool blurred: !!backdrop && backdrop.visible && backdrop.status === Image.Ready && width > 0 && height > 0
    property point origin: Qt.point(0, 0)
    // Layout settles in steps, so the card position is read again after a short delay.
    Timer { id: relocate; interval: 60; onTriggered: { frost.origin = frost.backdrop ? frost.mapToItem(frost.backdrop, 0, 0) : Qt.point(0, 0); source.scheduleUpdate(); } }
    Component.onCompleted: relocate.restart()
    onBlurredChanged: relocate.restart()
    onXChanged: relocate.restart()
    onYChanged: relocate.restart()
    onWidthChanged: relocate.restart()
    onHeightChanged: relocate.restart()
    Connections { target: frost.parent; ignoreUnknownSignals: true; function onXChanged() { relocate.restart(); } function onYChanged() { relocate.restart(); } }
    Connections { target: frost.backdrop; ignoreUnknownSignals: true; function onWidthChanged() { relocate.restart(); } function onHeightChanged() { relocate.restart(); } function onStatusChanged() { relocate.restart(); } }
    ShaderEffectSource {
        id: source
        visible: false
        live: false
        sourceItem: frost.blurred ? frost.backdrop : null
        sourceRect: Qt.rect(frost.origin.x, frost.origin.y, frost.width, frost.height)
        width: frost.width; height: frost.height
        onSourceRectChanged: scheduleUpdate()
    }
    Rectangle { id: mask; anchors.fill: parent; radius: frost.radius; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        visible: frost.blurred
        source: source
        autoPaddingEnabled: false
        blurEnabled: true; blur: 1; blurMax: 48; blurMultiplier: .6
        saturation: .25
        maskEnabled: true; maskSource: mask
        maskThresholdMin: .5; maskSpreadAtMin: 1
    }
    Rectangle {
        anchors.fill: parent
        radius: frost.radius
        color: Theme.alpha(frost.fill, frost.tint)
        border.width: 1; border.color: Theme.glassEdge
        Behavior on color { ColorAnimation { duration: Theme.motion(240) } }
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: Math.max(0, frost.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.glassHighlight }
                GradientStop { position: .35; color: "transparent" }
            }
        }
    }
}
