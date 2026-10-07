import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// Compact tonal notification. Popups and the inbox share it. A click runs the default action.
Rectangle {
    id: card
    required property var entry
    property bool popup: false
    property bool expanded: false
    // Grouped inbox rows hide the app line because the group header shows it.
    property bool showApp: true
    readonly property var notice: entry ? entry.notification : null
    readonly property bool critical: notice && notice.urgency === NotificationUrgency.Critical
    readonly property var actions: notice ? notice.actions.filter(a => a.identifier !== "default") : []
    readonly property var defaultAction: notice ? notice.actions.find(a => a.identifier === "default") : undefined
    readonly property string iconSource: {
        if (!notice) return "";
        const image = notice.image || "";
        if (/^(image:|file:|\/)/.test(image)) return image;
        const icon = notice.appIcon || "";
        if (!icon) return "";
        return icon.startsWith("/") || icon.startsWith("file:") || icon.startsWith("image:") ? icon : Quickshell.iconPath(icon, true);
    }
    // Controller: X dismisses the notification.
    function controllerAlternate() { Notifier.dismiss(entry); }
    implicitHeight: content.implicitHeight + 24
    radius: Theme.shapeLg
    color: critical ? Theme.mix(Theme.level(3), Theme.error, .12) : Theme.level(popup ? 3 : 2)
    // Popups slide in from the right edge and fade in.
    property real arrival: popup ? 0 : 1
    opacity: arrival
    transform: Translate { x: (1 - card.arrival) * 24 }
    NumberAnimation on arrival { running: card.popup; from: 0; to: 1; duration: Theme.motion(Theme.durMedium); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate }
    HoverHandler { id: hover; onHoveredChanged: if (card.entry) card.entry.hovered = hovered }
    Component.onDestruction: if (entry) entry.hovered = false
    Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.stateLayer; opacity: bodyMouse.pressed ? .10 : hover.hovered ? .04 : 0 }
    MouseArea {
        id: bodyMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: {
            const entry = card.entry;
            if (card.defaultAction) { card.defaultAction.invoke(); if (entry && entry.notification) Notifier.hidePopup(entry); }
            else if (card.popup) { Hub.targetScreen = Notifier.popupScreen; Hub.page = "notifications"; }
            else { card.expanded = !card.expanded; if (entry) { entry.read = true; Notifier.refresh(); } }
        }
    }
    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
        spacing: 12
        // App icon or sender image on a squircle.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40; Layout.preferredHeight: 40
            radius: Theme.shapeSm
            color: card.critical ? Theme.alpha(Theme.error, .18) : Theme.primaryContainer
            clip: true
            Image {
                id: appIcon; anchors.centerIn: parent
                readonly property bool photo: card.notice && /^(image:|file:|\/)/.test(card.notice.image || "")
                width: photo ? parent.width : 24; height: width
                source: card.iconSource; fillMode: Image.PreserveAspectCrop
                sourceSize.width: 80; sourceSize.height: 80; asynchronous: true
                visible: status === Image.Ready
            }
            Glyph { anchors.centerIn: parent; visible: !appIcon.visible; name: card.critical ? "priority_high" : "bell"; font.pixelSize: 20; color: card.critical ? Theme.error : Theme.onContainer }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 1
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                visible: card.showApp || card.critical
                MText { visible: card.showApp; text: card.notice ? card.notice.appName || "App" : ""; role: "labelS"; color: Theme.subtext; Layout.maximumWidth: 180 }
                MText { visible: card.showApp; text: "·"; role: "labelS"; color: Theme.subtext }
                MText { visible: card.showApp; text: card.entry ? Notifier.age(card.entry.received) : ""; role: "labelS"; color: Theme.subtext }
                MText { visible: card.critical; text: "Important"; role: "labelS"; font.weight: Font.Bold; color: Theme.error }
                Item { Layout.fillWidth: true }
            }
            MText {
                id: summaryText; Layout.fillWidth: true; text: card.notice ? card.notice.summary : ""
                wrapMode: Text.Wrap; maximumLineCount: card.expanded ? 6 : 1; role: "titleS"
            }
            MText {
                id: bodyText; Layout.fillWidth: true; visible: text.length > 0
                text: card.notice ? card.notice.body : ""
                wrapMode: Text.Wrap; maximumLineCount: card.expanded ? 40 : 2; role: "bodyS"; color: Theme.subtext
            }
            Flow {
                visible: card.actions.length > 0
                Layout.fillWidth: true; Layout.topMargin: 8; spacing: 6
                Repeater {
                    model: card.actions
                    MButton {
                        required property var modelData
                        text: modelData.text || "Action"
                        compact: true; tonal: true; implicitHeight: 32
                        implicitWidth: Math.min(content.width - 52, actionMetrics.advanceWidth + 32)
                        TextMetrics { id: actionMetrics; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; text: modelData.text || "Action" }
                        onClicked: { const entry = card.entry; modelData.invoke(); if (entry && entry.notification) Notifier.hidePopup(entry); }
                    }
                }
            }
        }
        // Dismiss and expand controls. On popups they appear on hover.
        Column {
            Layout.alignment: Qt.AlignTop
            spacing: 2
            opacity: !card.popup || hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durShort) } }
            MButton { icon: "close"; compact: true; implicitWidth: 30; implicitHeight: 30; ink: Theme.subtext; tooltip: "Dismiss"; onClicked: Notifier.dismiss(card.entry) }
            MButton {
                visible: !card.popup && (bodyText.truncated || summaryText.truncated || card.expanded)
                icon: card.expanded ? "expand_less" : "expand_more"; compact: true; implicitWidth: 30; implicitHeight: 30; ink: Theme.subtext
                tooltip: card.expanded ? "Show less" : "Show more"
                onClicked: { card.expanded = !card.expanded; if (card.entry) { card.entry.read = true; Notifier.refresh(); } }
            }
        }
    }
}
