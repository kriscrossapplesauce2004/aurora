import QtQuick
import QtQuick.Layouts
import Quickshell
// Lock screen extras: notifications (app and title only by default), a torch button and the ambient clock.
Item {
    id: extras
    // The lock scene that hosts this item.
    property Item scene: null
    readonly property string privacy: Hub.prefs.lockNotifications || "title"
    readonly property bool idleReady: Hub.prefs.ambientClock !== false && !!scene && !scene.greeter
    readonly property bool notesAllowed: privacy !== "off" && privacy !== "count"
    property alias pill: activityPill
    property bool ambientOn: false
    function wake() { ambientOn = false; idle.restart(); }
    onSceneChanged: idle.restart()
    Timer { id: idle; interval: 45000; running: extras.idleReady && !extras.ambientOn && !(extras.scene && extras.scene.revealed); onTriggered: extras.ambientOn = true }
    // A key press or revealing the auth column ends ambient mode.
    Connections { target: extras.scene; function onRevealedChanged() { if (extras.scene.revealed) extras.wake(); } }
    // Tests set fixtureItems to show cards without a notification server.
    property var fixtureItems: null
    readonly property var items: fixtureItems !== null ? fixtureItems : realItems
    readonly property var realItems: {
        const revision = Notifier.revision;
        if (privacy === "off" || privacy === "count") return [];
        return Notifier.inbox.slice().sort((a, b) => b.received - a.received).slice(0, 3);
    }
    Column {
        id: cards
        visible: extras.items.length > 0 && !!extras.scene && !extras.scene.revealed && !extras.scene.greeter
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(parent.height * .5, activityPill.visible && activityPill.pinned ? activityPill.y + activityPill.height + 14 : 0)
        width: Math.min(380, parent.width - 48)
        spacing: 6
        Repeater {
            model: extras.items
            Rectangle {
                id: card
                required property var modelData
                width: cards.width; height: 60; radius: 22
                color: Theme.alpha(Theme.level(3), .82)
                Row {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                    Rectangle {
                        width: 36; height: 36; radius: 12; anchors.verticalCenter: parent.verticalCenter; color: Theme.secondaryContainer
                        Image {
                            anchors.fill: parent; anchors.margins: 6; sourceSize: Qt.size(48, 48)
                            source: card.modelData.notification.appIcon ? Quickshell.iconPath(card.modelData.notification.appIcon, true) : ""
                            visible: status === Image.Ready
                        }
                        Glyph { anchors.centerIn: parent; visible: card.modelData.notification.appIcon === ""; name: "notifications"; font.pixelSize: 20; color: Theme.onSecondaryContainer }
                    }
                    Column {
                        width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter
                        MText { width: parent.width; elide: Text.ElideRight; text: card.modelData.notification.appName || "App"; font.pixelSize: 11; font.weight: Font.Medium; color: Theme.subtext }
                        // Only the title is shown. Message bodies stay hidden until unlock.
                        MText { width: parent.width; elide: Text.ElideRight; text: card.modelData.notification.summary || "New notification"; font.pixelSize: 14; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }
    // Live activities sit between the clock and the notification cards. Lock privacy applies to them.
    ActivityPill {
        id: activityPill
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * .39
        visible: opacity > 0 && !!extras.scene && !extras.scene.revealed && !extras.scene.greeter
        stack: true; framed: true; hideNotes: !extras.notesAllowed
        maxCompact: 220; maxExpanded: Math.min(380, parent.width - 48)
        onPinnedChanged: if (pinned) extras.wake()
    }
    PhoneTorch {
        visible: PhoneState.torch.available && !!extras.scene && !extras.scene.greeter
        anchors.right: parent.right; anchors.rightMargin: 28
        anchors.bottom: parent.bottom; anchors.bottomMargin: 112
        implicitWidth: 56; implicitHeight: 56
    }
    Loader {
        anchors.fill: parent
        active: extras.ambientOn
        sourceComponent: AmbientClock { onWoken: extras.wake() }
    }
}
