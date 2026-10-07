import QtQuick
import QtQuick.Layouts
import Quickshell

// Inbox grouped by app. Groups are ordered by their newest notification.
Column {
    id: groups
    property var expandedApps: ({})
    readonly property var model: {
        const revision = Notifier.revision;
        const map = {};
        const order = [];
        Notifier.inbox.slice().sort((a, b) => b.received - a.received).forEach(e => {
            const app = e.notification.appName || "App";
            if (!map[app]) { map[app] = {app: app, icon: e.notification.appIcon || "", entries: []}; order.push(app); }
            map[app].entries.push(e);
        });
        return order.map(app => map[app]);
    }
    spacing: 10
    Repeater {
        model: groups.model
        Column {
            id: group
            required property var modelData
            readonly property bool open: !!groups.expandedApps[modelData.app]
            readonly property int extra: modelData.entries.length - 1
            width: groups.width
            spacing: 4
            // Group header: app, count, expand and clear.
            RowLayout {
                width: parent.width; height: 30; spacing: 8
                Image {
                    Layout.preferredWidth: 16; Layout.preferredHeight: 16; Layout.leftMargin: 6
                    source: group.modelData.icon ? (group.modelData.icon.startsWith("/") || group.modelData.icon.startsWith("file:") ? group.modelData.icon : Quickshell.iconPath(group.modelData.icon, true)) : ""
                    sourceSize: Qt.size(32, 32); visible: status === Image.Ready
                }
                MText { text: group.modelData.app; role: "label"; font.weight: Font.DemiBold; color: Theme.subtext; Layout.fillWidth: true }
                MButton {
                    visible: group.extra > 0
                    text: group.open ? "Show less" : "+" + group.extra; compact: true; implicitHeight: 28; ink: Theme.subtext
                    onClicked: { const next = Object.assign({}, groups.expandedApps); next[group.modelData.app] = !group.open; groups.expandedApps = next; }
                }
                MButton { icon: "close"; compact: true; implicitWidth: 28; implicitHeight: 28; ink: Theme.subtext; tooltip: "Clear " + group.modelData.app; onClicked: group.modelData.entries.forEach(e => Notifier.dismiss(e)) }
            }
            Repeater {
                model: group.open ? group.modelData.entries : group.modelData.entries.slice(0, 1)
                NotificationCard { required property var modelData; entry: modelData; width: group.width; showApp: false }
            }
            // Collapsed groups show a stacked edge for the hidden notifications.
            Rectangle {
                visible: !group.open && group.extra > 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24; height: 6; radius: 3
                color: Theme.level(3); opacity: .8
            }
        }
    }
}
