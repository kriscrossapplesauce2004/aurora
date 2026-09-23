import QtQuick
Rectangle {
    id: surface
    property real translucency: Hub.prefs.glass
    property bool elevated: false
    property bool sheen: true
    radius: 32
    color: Theme.alpha(elevated ? Theme.surfaceHigh : Theme.glassTint, translucency)
    border.width: 1
    border.color: Theme.glassEdge
    Behavior on color { ColorAnimation { duration: Theme.motion(240) } }
    // Inner rim: a hairline light edge inside the border makes the glass read as a thick pane.
    Rectangle {
        z: -1
        visible: surface.sheen && surface.width > 0
        anchors.fill: parent
        anchors.margins: surface.border.width
        radius: Math.max(0, surface.radius - surface.border.width)
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha("#ffffff", Theme.light ? .35 : .05)
        // Top glint: light falls on the upper edge only, so no dark band is added below.
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: Math.min(parent.height, Math.max(24, surface.radius * 1.5))
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.alpha("#ffffff", Theme.light ? .22 : .045) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
