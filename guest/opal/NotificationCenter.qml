import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Full inbox page: header, quiet mode, grouped list.
Item {
    id: center
    property bool confirmClear: false
    Component.onCompleted: Notifier.centerOpen = true
    Component.onDestruction: Notifier.centerOpen = false
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            MText { text: "Notifications"; role: "headline"; Layout.fillWidth: true }
            MButton { icon: Hub.dnd ? "quiet" : "bell"; filled: Hub.dnd; compact: true; tooltip: Hub.dnd ? "Turn off Do not disturb" : "Do not disturb"; onClicked: Hub.set("dnd", !Hub.dnd) }
            MButton { visible: Notifier.inbox.length > 0; text: center.confirmClear ? "Confirm" : "Clear all"; compact: true; filled: center.confirmClear; onClicked: { if (center.confirmClear) { Notifier.clear(); center.confirmClear = false; } else center.confirmClear = true; } }
        }
        MText { visible: Hub.dnd; Layout.fillWidth: true; text: "Do not disturb is on. Notifications arrive silently."; role: "bodyS"; color: Theme.subtext; wrapMode: Text.Wrap }
        SuggestionChips { Layout.fillWidth: true }
        Flickable {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentHeight: list.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            NotificationGroups { id: list; width: parent.width }
            ColumnLayout {
                anchors.centerIn: parent; width: parent.width - 32; visible: Notifier.inbox.length === 0; spacing: 8
                Glyph { Layout.alignment: Qt.AlignHCenter; name: "bell"; color: Theme.muted; font.pixelSize: 32 }
                MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "You're all caught up"; role: "titleS" }
            }
        }
    }
}
