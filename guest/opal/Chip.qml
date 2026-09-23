import QtQuick
import QtQuick.Layouts
// M3 assist or filter chip with optional leading and trailing icons.
Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property string trailingIcon: ""
    property string tooltip: text
    property bool selected: false
    property bool glass: true
    readonly property color ink: selected ? Theme.onSecondaryContainer : Theme.text
    signal clicked()
    readonly property real leftPad: icon !== "" || selected ? 10 : 15
    readonly property real rightPad: trailingIcon !== "" ? 8 : 14
    implicitWidth: row.implicitWidth + leftPad + rightPad
    implicitHeight: 32
    radius: height / 2
    color: selected ? Theme.secondaryContainer : glass ? Theme.alpha(Theme.glassRaised, Theme.light ? .72 : .55) : "transparent"
    border.width: selected || glass ? 0 : 1
    border.color: Theme.alpha(Theme.subtext, .35)
    Behavior on color { ColorAnimation { duration: Theme.motion(160) } }
    scale: mouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.motion(120) } }
    Rectangle { anchors.fill: parent; radius: parent.radius; color: root.ink; opacity: mouse.pressed ? .12 : mouse.containsMouse || root.activeFocus ? .08 : 0 }
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: parent.radius + 3; color: "transparent"; border.width: 2; border.color: Theme.primary; visible: root.activeFocus }
    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: root.leftPad
        width: Math.min(implicitWidth, root.width - root.leftPad - root.rightPad)
        spacing: 6
        Glyph { visible: root.icon !== "" || root.selected; name: root.selected && root.icon === "" ? "check" : root.icon; font.pixelSize: 17; color: root.selected ? root.ink : Theme.primary }
        MText { Layout.fillWidth: true; text: root.text; color: root.ink; font.pixelSize: 12; font.weight: Font.Medium }
        Glyph { visible: root.trailingIcon !== ""; name: root.trailingIcon; font.pixelSize: 17; color: Theme.subtext }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Accessible.role: Accessible.Button
    Accessible.name: tooltip
    Accessible.onPressAction: clicked()
}
