import QtQuick
// Ambient lock clock: black, dim and slowly drifting so no pixel stays lit. A touch wakes the lock screen.
Item {
    id: ambient
    signal woken()
    readonly property int minute: Hub.now.getMinutes() + Hub.now.getHours() * 60
    // The drift is zero with reduced motion, and the text is still dim.
    readonly property real driftX: Theme.reduceMotion ? 0 : Math.sin(minute * 2.1) * Math.min(48, width * .08)
    readonly property real driftY: Theme.reduceMotion ? 0 : Math.cos(minute * 1.7) * Math.min(48, height * .05)
    Rectangle { anchors.fill: parent; color: "#000000" }
    Column {
        id: face
        width: parent.width
        x: ambient.driftX
        y: parent.height * .36 + ambient.driftY
        spacing: 6
        Behavior on x { enabled: !Theme.reduceMotion; NumberAnimation { duration: 3000; easing.type: Easing.InOutSine } }
        Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: 3000; easing.type: Easing.InOutSine } }
        MText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(Hub.now, "HH:mm")
            font.pixelSize: Math.min(180, ambient.width * .28)
            font.weight: Font.Light
            font.variableAxes: ({"wdth": 100, "ROND": 100})
            font.features: {"tnum": 1}
            color: Qt.rgba(1, 1, 1, .5)
        }
        MText { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDateTime(Hub.now, "dddd d MMMM"); font.pixelSize: 18; color: Qt.rgba(1, 1, 1, .36) }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            topPadding: 10
            MText { visible: Hub.status.battery >= 0; text: (Hub.status.charging ? "Charging " : "") + Hub.status.battery + "%"; font.pixelSize: 15; color: Qt.rgba(1, 1, 1, .36) }
            MText { visible: Hub.unread > 0; text: Hub.unread + (Hub.unread === 1 ? " notification" : " notifications"); font.pixelSize: 15; color: Qt.rgba(1, 1, 1, .36) }
        }
    }
    MouseArea { anchors.fill: parent; onPressed: ambient.woken() }
    Accessible.role: Accessible.Button
    Accessible.name: "Ambient clock. Touch to wake."
}
