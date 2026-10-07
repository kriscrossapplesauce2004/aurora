import QtQuick
// Tonal pill for bar groups. Strong islands use the primary container.
Rectangle {
    id: island
    property bool strong: false
    property bool hovered: hover.hovered
    radius: height / 2
    color: strong ? Theme.primaryContainer : Theme.level(3)
    Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
    HoverHandler { id: hover }
}
