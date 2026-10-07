import QtQuick
// Tonal container. Level sets the tone; translucency only lets a little compositor blur through.
Rectangle {
    id: surface
    property real translucency: 1
    property bool elevated: false
    property int level: elevated ? 3 : 2
    property bool outlined: false
    radius: Theme.shapeXl
    color: Theme.alpha(Theme.level(level), Theme.panelAlpha(translucency))
    border.width: outlined ? 1 : 0
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
}
