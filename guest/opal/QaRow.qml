import QtQuick
import QtQuick.Layouts

// Controller-friendly row: action, toggle, slider, choice or info. The controller* members are called by ControllerFocus.
Rectangle {
    id: row
    property string kind: "action"
    property string icon: ""
    property string title: ""
    property string detail: ""
    // Text in the chip at the end of a choice or info row.
    property string choice: ""
    property bool checked: false
    property real value: 0
    property real from: 0
    property real to: 100
    property string unit: "%"
    // How many slider steps one D-pad press moves.
    property int pressSteps: 5
    property bool danger: false
    property bool controllerFocused: false
    readonly property bool controllerFocusable: kind !== "info"
    readonly property bool controllerLeaf: true
    readonly property bool slider: kind === "slider"
    signal activated()
    signal adjusted(int delta)
    signal sliderMoved(real value)
    signal alternate()

    function controllerActivate() { if (kind === "choice") adjusted(1); else activated(); }
    function controllerAdjust(delta) {
        if (kind === "slider") {
            for (let i = 0; i < pressSteps; i++) { if (delta > 0) track.increase(); else track.decrease(); }
            track.moved();
            return true;
        }
        if (kind === "choice") { adjusted(delta); return true; }
        return false;
    }
    function controllerAlternate() { alternate(); }

    implicitHeight: slider ? 88 : detail !== "" ? 68 : 60
    radius: Theme.shapeLg
    color: danger ? Theme.mix(Theme.level(3), Theme.error, controllerFocused ? .26 : .14) : controllerFocused || hover.hovered ? Theme.level(4) : Theme.level(3)
    Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
    scale: press.pressed ? .985 : 1
    Behavior on scale { NumberAnimation { duration: Theme.motion(120); easing.type: Easing.OutCubic } }
    HoverHandler { id: hover }
    MouseArea {
        id: press
        anchors.fill: parent; z: -1
        enabled: row.kind !== "info"
        cursorShape: Qt.PointingHandCursor
        onClicked: row.controllerActivate()
    }
    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: row.slider ? 10 : 0; bottomMargin: row.slider ? 10 : 0 }
        spacing: 14
        Rectangle {
            Layout.preferredWidth: 40; Layout.preferredHeight: 40; Layout.alignment: row.slider ? Qt.AlignTop : Qt.AlignVCenter
            radius: 20
            color: row.danger ? Theme.alpha(Theme.error, .18) : row.checked && row.kind === "toggle" ? Theme.primaryContainer : Theme.secondaryContainer
            Glyph { anchors.centerIn: parent; name: row.icon; font.pixelSize: 22; color: row.danger ? Theme.error : row.checked && row.kind === "toggle" ? Theme.onContainer : Theme.onSecondaryContainer }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            RowLayout {
                Layout.fillWidth: true
                MText { Layout.fillWidth: true; text: row.title; role: "titleS"; color: row.danger ? Theme.error : Theme.text }
                MText { visible: row.slider; text: Math.round(row.value) + row.unit; role: "label"; color: Theme.subtext; font.features: {"tnum": 1} }
            }
            MText { visible: row.detail !== "" && !row.slider; Layout.fillWidth: true; text: row.detail; role: "labelS"; color: Theme.subtext }
            ExpressiveSlider {
                id: track
                visible: row.slider
                Layout.fillWidth: true; Layout.preferredHeight: 32
                property bool controllerSkip: true
                compact: true; trackHeight: 20; showIcon: false
                from: row.from; to: row.to; stepSize: 1
                value: row.value
                onMoved: row.sliderMoved(value)
                Accessible.name: row.title
            }
        }
        MSwitch { visible: row.kind === "toggle"; checked: row.checked; onToggled: row.activated() }
        Rectangle {
            visible: row.kind === "choice" || row.kind === "info" && row.choice !== ""
            Layout.preferredHeight: 34; Layout.preferredWidth: chip.implicitWidth + (row.kind === "choice" ? 56 : 28)
            radius: 17
            color: row.kind === "choice" ? Theme.primaryContainer : Theme.alpha(Theme.primary, .14)
            Glyph { visible: row.kind === "choice"; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } name: "chevron_left"; font.pixelSize: 20; color: Theme.onContainer }
            MText { id: chip; anchors.centerIn: parent; text: row.choice; role: "label"; font.weight: Font.Bold; color: row.kind === "choice" ? Theme.onContainer : Theme.primary; font.features: {"tnum": 1} }
            Glyph { visible: row.kind === "choice"; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } name: "chevron_right"; font.pixelSize: 20; color: Theme.onContainer }
        }
        Glyph { visible: row.kind === "action" && row.choice === ""; name: "chevron_right"; font.pixelSize: 22; color: Theme.muted }
    }
    Accessible.role: Accessible.Button
    Accessible.name: title
}
