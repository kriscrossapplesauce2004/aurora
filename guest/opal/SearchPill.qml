import QtQuick
import QtQuick.Layouts
// Shelf search pill: a quiet solid field with a colour mark and tools. It shows no text, like a phone search bar.
Island {
    id: pill
    property var output: null
    property bool wide: true
    function open(prefix) {
        Hub.targetScreen = output;
        Hub.openSearch();
        if (prefix) Hub.query = prefix;
    }
    Rectangle {
        id: field
        anchors.fill: parent; anchors.margins: 4; radius: height / 2
        color: Theme.light ? "#ffffff" : Theme.mix(Theme.base, Theme.primaryContainer, .55)
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.stateLayer; opacity: fieldMouse.pressed ? .12 : fieldMouse.containsMouse ? .06 : 0; Behavior on opacity { NumberAnimation { duration: Theme.motion(120) } } }
        MouseArea { id: fieldMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.open("") }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 4; spacing: 2
            // Colour mark: four quarter dots in the theme's accent roles.
            Item {
                Layout.preferredWidth: 20; Layout.preferredHeight: 20
                Repeater {
                    model: [Theme.primary, Theme.tertiary, Theme.secondary, Theme.light ? Theme.containerInk : Theme.primaryContainer]
                    Rectangle {
                        required property color modelData
                        required property int index
                        width: 8; height: 8; radius: 4; color: modelData
                        x: index % 2 ? 11 : 1; y: index < 2 ? 1 : 11
                        scale: fieldMouse.containsMouse && !Theme.reduceMotion ? 1.18 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.motion(220) + index * 30; easing.type: Easing.OutCubic } }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            MButton { visible: pill.wide; icon: "calculate"; compact: true; implicitWidth: 30; implicitHeight: 30; hoverHalo: true; ink: Theme.subtext; tooltip: "Calculator"; onClicked: pill.open("= ") }
            MButton { visible: pill.wide; icon: "clipboard"; compact: true; implicitWidth: 30; implicitHeight: 30; hoverHalo: true; ink: Theme.subtext; tooltip: "Clipboard history"; onClicked: { Hub.targetScreen = pill.output; Hub.toggleClipboard(); } }
            MButton { icon: "capture"; compact: true; implicitWidth: 30; implicitHeight: 30; hoverHalo: true; ink: Theme.subtext; tooltip: "Take a screenshot"; onClicked: Hub.screenShot() }
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Search apps, open windows and actions"
    Accessible.onPressAction: open("")
}
