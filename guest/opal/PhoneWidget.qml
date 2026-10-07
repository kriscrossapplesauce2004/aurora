import QtQuick
import QtQuick.Layouts
// One phone home widget. Edit mode shows a remove badge.
Item {
    id: widget
    property string kind: "glance"
    property bool editing: false
    signal remove()
    signal longPressed()
    signal tapped()
    implicitHeight: loader.item ? loader.item.implicitHeight : 0
    height: implicitHeight
    Loader {
        id: loader
        width: parent.width
        sourceComponent: widget.kind === "glance" ? glance : widget.kind === "stack" ? stack : widget.kind === "media" ? media : widget.kind === "calendar" ? calendar : widget.kind === "battery" ? battery : focus
    }
    TapHandler { onLongPressed: widget.longPressed(); onTapped: widget.tapped() }
    Rectangle {
        visible: widget.editing
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: -4
        width: 28; height: 28; radius: 14; color: Theme.level(4)
        Glyph { anchors.centerIn: parent; name: "remove"; font.pixelSize: 18; color: Theme.text }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: widget.remove() }
    }
    // Glance: a large clock with the date and one status line.
    Component {
        id: glance
        Item {
            implicitHeight: glanceColumn.implicitHeight + 16
            Column {
                id: glanceColumn; x: 6; y: 8; width: parent.width - 12; spacing: 2
                MText {
                    text: Qt.formatDateTime(Hub.now, "HH:mm")
                    font.pixelSize: Math.min(96, parent.width * .21); font.weight: Font.Black
                    font.variableAxes: ({"wdth": 125, "ROND": 100}); font.features: {"tnum": 1}
                    color: Theme.primary
                }
                MText { text: Qt.formatDateTime(Hub.now, "dddd d MMMM"); role: "title" }
                Row {
                    spacing: 6
                    Glyph { font.pixelSize: 16; color: Theme.primary; name: Hub.unread ? "notifications_unread" : Hub.status.charging ? "bolt" : Hub.dnd ? "do_not_disturb_on" : Hub.status.track ? "music_note" : "wb_twilight"; anchors.verticalCenter: parent.verticalCenter }
                    MText {
                        anchors.verticalCenter: parent.verticalCenter; role: "label"; color: Theme.subtext
                        text: Hub.unread ? Hub.unread + (Hub.unread === 1 ? " new notification" : " new notifications") : Hub.status.track ? Hub.status.track : Hub.dnd ? "Do not disturb is on" : Hub.status.battery >= 0 ? Hub.status.battery + "%" + (Hub.status.charging ? " · charging" : "") : "All quiet"
                    }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: Hub.page = "notifications" }
        }
    }
    Component { id: stack; SmartStack { width: widget.width } }
    Component { id: media; Item { implicitHeight: Hub.status.track !== "" ? card.implicitHeight : emptyMedia.implicitHeight + 24
        MediaCard { id: card; width: parent.width; visible: Hub.status.track !== ""; compact: true }
        Rectangle { visible: Hub.status.track === ""; width: parent.width; height: parent.implicitHeight; radius: Theme.shapeXl; color: Theme.level(2)
            MText { id: emptyMedia; anchors.centerIn: parent; text: "Nothing playing"; role: "body"; color: Theme.subtext } } } }
    Component { id: calendar; CalendarWidget { implicitHeight: 300 } }
    Component { id: battery; Rectangle {
        implicitHeight: batteryColumn.implicitHeight + 28; radius: Theme.shapeXl; color: Theme.level(2)
        Column { id: batteryColumn; x: 16; y: 14; width: parent.width - 32; spacing: 10
            Repeater {
                model: (Hub.status.batteries || []).length ? Hub.status.batteries : [{name: "This device", percent: Math.max(0, Hub.status.battery), charging: Hub.status.charging}]
                RowLayout { required property var modelData; width: batteryColumn.width; spacing: 10
                    Glyph { name: modelData.charging ? "charging" : "battery"; font.pixelSize: 20; color: Theme.primary }
                    ColumnLayout { Layout.fillWidth: true; spacing: 4
                        MText { text: modelData.name; role: "label" }
                        Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Theme.alpha(Theme.primary, .2)
                            Rectangle { width: parent.width * Math.max(0, Math.min(100, modelData.percent)) / 100; height: 6; radius: 3; color: Theme.primary } } }
                    MText { text: modelData.percent + "%"; role: "titleS"; font.features: {"tnum": 1} } } } } } }
    Component { id: focus; Item { implicitHeight: Hub.focusRunning ? focusCard.implicitHeight : 56
        FocusCard { id: focusCard; width: parent.width; visible: Hub.focusRunning }
        MButton { visible: !Hub.focusRunning; width: parent.width; icon: "timer"; text: "Start a 25 minute focus"; tonal: true; onClicked: Hub.timerToggle() } } }
}
