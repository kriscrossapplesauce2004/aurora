import QtQuick
// Translucent glass container for shelf and desktop islands. The compositor blurs what is behind it.
Rectangle {
    id: island
    property bool strong: false
    property bool hovered: hover.hovered
    radius: height / 2
    color: strong ? Theme.alpha(Theme.light ? Theme.primaryContainer : Theme.mix(Theme.base, Theme.primary, .42), Math.max(.72, Hub.prefs.glass + .22))
                  : Theme.alpha(Theme.glassIsland, Math.max(.4, Math.min(.84, Hub.prefs.glass + .04)))
    border.width: 1
    border.color: Theme.glassEdge
    Behavior on color { ColorAnimation { duration: Theme.motion(200) } }
    HoverHandler { id: hover }
    Rectangle {
        z: -1
        anchors.fill: parent; anchors.margins: 1
        radius: Math.max(0, island.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.glassHighlight }
            GradientStop { position: .5; color: "transparent" }
        }
    }
}
