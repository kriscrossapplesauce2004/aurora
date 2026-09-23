import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Surface {
    id: card
    required property var entry
    property bool popup: false
    property bool expanded: false
    readonly property var notice: entry ? entry.notification : null
    readonly property bool critical: notice && notice.urgency === NotificationUrgency.Critical
    readonly property var actions: notice ? notice.actions : []
    implicitHeight: content.implicitHeight + 28
    radius: 24
    translucency: popup ? Math.max(.68, Hub.prefs.glass) : .42
    elevated: !popup
    border.color: critical ? Theme.alpha(Theme.error,.7) : Theme.glassEdge
    border.width: critical ? 2 : 1
    HoverHandler { id: hover; onHoveredChanged: if (card.entry) card.entry.hovered = hovered }
    Component.onDestruction: if (entry) entry.hovered = false
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Rectangle {
                width: 32; height: 32; radius: 16; color: card.critical ? Theme.alpha(Theme.error,.18) : Theme.primaryContainer
                Image {
                    id: appIcon; anchors.centerIn: parent; width: 18; height: 18
                    source: card.notice && card.notice.appIcon ? (card.notice.appIcon.startsWith("/") || card.notice.appIcon.startsWith("file:") || card.notice.appIcon.startsWith("image:") ? card.notice.appIcon : Quickshell.iconPath(card.notice.appIcon, true)) : ""
                    sourceSize.width: 24; sourceSize.height: 24
                    visible: status === Image.Ready
                }
                Glyph { anchors.centerIn: parent; visible: !appIcon.visible; name: card.critical ? "priority_high" : "bell"; font.pixelSize: 17; color: card.critical ? Theme.error : Theme.onContainer }
            }
            MText { text: card.notice ? card.notice.appName || "Application" : ""; textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.DemiBold }
            Rectangle { visible: card.entry && !card.entry.read && !card.popup; width: 6; height: 6; radius: 3; color: Theme.primary }
            MText { text: card.entry ? Notifier.age(card.entry.received) : ""; font.pixelSize: 11; color: Theme.muted }
            MButton { icon: "close"; compact: true; implicitWidth: 28; implicitHeight: 28; tooltip: "Dismiss notification"; onClicked: Notifier.dismiss(card.entry) }
        }
        MText { visible: card.critical; text: "IMPORTANT"; font.pixelSize: 10; font.letterSpacing: 1; font.weight: Font.DemiBold; color: Theme.error }
        MText {
            id: summaryText; Layout.fillWidth: true; text: card.notice ? card.notice.summary : ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: card.expanded ? 50 : 2
            elide: Text.ElideRight; font.pixelSize: 15; font.weight: Font.DemiBold
        }
        MText {
            id: body; Layout.fillWidth: true; visible: text.length > 0
            text: card.notice ? card.notice.body : ""; textFormat: Text.PlainText
            wrapMode: Text.Wrap; maximumLineCount: card.expanded ? 1000 : card.popup ? 3 : 4
            elide: Text.ElideRight; font.pixelSize: 13; color: Theme.subtext
        }
        Image {
            Layout.fillWidth: true; Layout.preferredHeight: visible ? 120 : 0
            visible: source.toString() !== "" && status === Image.Ready
            source: card.notice && /^(image:|file:|\/)/.test(card.notice.image) ? card.notice.image : ""
            fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 640; sourceSize.height: 240
        }
        Flow {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: card.actions
                MButton {
                    required property var modelData
                    text: modelData.text || (modelData.identifier === "default" ? "Open" : "Action")
                    implicitWidth: Math.min(content.width, Math.max(64, actionMetrics.advanceWidth + 40))
                    TextMetrics { id: actionMetrics; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; text: modelData.text }
                    compact: true; tonal: true; implicitHeight: 34
                    onClicked: { const entry = card.entry; modelData.invoke(); if (entry.notification) Notifier.hidePopup(entry); }
                }
            }
            MButton {
                visible: body.truncated || summaryText.truncated || card.expanded
                text: card.expanded ? "Show less" : "Show more"; compact: true; implicitHeight: 34
                onClicked: { card.expanded = !card.expanded; if (card.entry) {card.entry.read=true;Notifier.refresh();} }
            }
            MButton { visible: card.popup; text: "Inbox"; compact: true; implicitHeight: 34; onClicked: { Hub.targetScreen=Notifier.popupScreen;Hub.page="notifications"; } }
        }
    }
}
