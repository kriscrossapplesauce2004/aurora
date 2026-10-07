import QtQuick
// M3 switch: the handle grows when on and shows a check.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 52; implicitHeight: 32
    radius: height / 2
    color: checked ? Theme.primary : Theme.level(4)
    border.width: checked ? 0 : 2; border.color: Theme.alpha(Theme.subtext, .7)
    opacity: enabled ? 1 : .4
    Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
    Rectangle {
        readonly property real size: mouse.pressed ? 28 : sw.checked ? 24 : 16
        width: size; height: size; radius: size / 2
        x: sw.checked ? sw.width - width - 4 : (mouse.pressed ? 2 : 8)
        anchors.verticalCenter: parent.verticalCenter
        color: sw.checked ? Theme.onPrimary : Theme.subtext
        Behavior on x { NumberAnimation { duration: Theme.motion(Theme.durShort); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durShort) } }
        Glyph { anchors.centerIn: parent; visible: sw.checked; name: "check"; font.pixelSize: 16; color: Theme.primary }
    }
    MouseArea { id: mouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled(!sw.checked) }
    activeFocusOnTab: true
    Keys.onSpacePressed: toggled(!checked)
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
    Accessible.onPressAction: toggled(!checked)
}
