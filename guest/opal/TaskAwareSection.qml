import QtQuick
import QtQuick.Layouts
import Quickshell
// Task-aware home: what you were doing, from local data only. It hides when there is nothing to resume.
Column {
    id: section
    spacing: 8
    readonly property var files: (PhoneState.activity.files || []).slice(0, 5)
    readonly property var games: (PhoneState.activity.games || []).slice(0, 2)
    readonly property bool mediaPaused: Hub.status.track !== undefined && Hub.status.track !== "" && !Hub.status.playing
    // Windows other Opal Link devices have open. The device sends one session summary.
    readonly property var remote: (Hub.linkDevices || []).filter(d => d.paired && d.reachable && d.session && (d.session.title || d.session.track || d.session.appName))
    // One flat list keeps the order stable: remote work first, then media, games and files.
    readonly property var cards: {
        const list = [];
        remote.forEach(d => list.push({kind: "remote", device: d, id: "r" + d.id}));
        if (mediaPaused) list.push({kind: "media", id: "media"});
        games.forEach(g => list.push({kind: "game", game: g, id: "g" + g.id}));
        files.forEach(f => list.push({kind: "file", file: f, id: "f" + f.path}));
        return list;
    }
    visible: cards.length > 0
    function open(path) { Quickshell.execDetached(["xdg-open", path]); }
    function launchGame(g) { const full = Hub.games.find(x => x.id === g.id); if (full) Hub.launchGame(full); }
    function resume(d) {
        const app = Hub.apps.find(a => a.id === d.session.app || a.name === d.session.appName);
        if (app) Hub.launch(app); else Hub.message("Open " + (d.session.appName || "the app") + " on this device");
    }
    Component.onCompleted: PhoneState.refreshActivity()
    Timer { interval: 60000; repeat: true; running: section.visible && Hub.page === ""; onTriggered: PhoneState.refreshActivity() }
    RowLayout {
        width: parent.width
        spacing: 8
        Glyph { name: "history"; font.pixelSize: 16; color: Theme.primary; Layout.leftMargin: 6 }
        MText { text: "Pick up where you left off"; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.primary; Layout.fillWidth: true }
    }
    Flickable {
        width: parent.width
        height: 96
        contentWidth: row.width
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        Row {
            id: row
            spacing: 8
            Repeater {
                model: section.cards
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property string kind: modelData.kind
                    width: kind === "file" ? 172 : 196
                    height: 96
                    radius: 26
                    color: kind === "media" ? Theme.primaryContainer : kind === "game" ? Theme.tertiaryContainer : kind === "remote" ? Theme.level(3) : Theme.secondaryContainer
                    readonly property color ink: kind === "media" ? Theme.onContainer : kind === "game" ? Theme.onTertiaryContainer : kind === "remote" ? Theme.text : Theme.onSecondaryContainer
                    Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.stateLayer; opacity: tap.pressed ? .12 : 0; Behavior on opacity { NumberAnimation { duration: Theme.motion(100) } } }
                    Row {
                        anchors.fill: parent; anchors.margins: 14; spacing: 12
                        Rectangle {
                            width: 44; height: 44; radius: 14; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.alpha(card.ink, .12); clip: true
                            Image {
                                anchors.fill: parent; visible: card.kind === "game" && status === Image.Ready
                                source: card.kind === "game" ? card.modelData.game.cover : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(88, 88)
                            }
                            Glyph {
                                anchors.centerIn: parent; font.pixelSize: 24; color: card.ink
                                name: card.kind === "file" ? card.modelData.file.icon : card.kind === "media" ? "play_arrow" : card.kind === "game" ? "sports_esports" : "devices"
                            }
                        }
                        Column {
                            width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                            MText {
                                width: parent.width; elide: Text.ElideRight; font.pixelSize: 11; font.weight: Font.Medium; color: Theme.alpha(card.ink, .75)
                                text: card.kind === "file" ? "Recent file" : card.kind === "media" ? "Paused" : card.kind === "game" ? "Recently played" : card.modelData.device.name
                            }
                            MText {
                                width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap; font.pixelSize: 14; font.weight: Font.DemiBold; color: card.ink
                                text: card.kind === "file" ? card.modelData.file.title : card.kind === "media" ? Hub.status.track : card.kind === "game" ? card.modelData.game.title : (card.modelData.device.session.title || card.modelData.device.session.track || card.modelData.device.session.appName)
                            }
                            MText {
                                width: parent.width; elide: Text.ElideRight; font.pixelSize: 11; color: Theme.alpha(card.ink, .75)
                                text: card.kind === "file" ? card.modelData.file.ago : card.kind === "media" ? (Hub.status.artist || "Tap to resume") : card.kind === "game" ? card.modelData.game.ago : (card.modelData.device.session.appName || "Open here")
                            }
                        }
                    }
                    TapHandler {
                        id: tap
                        onTapped: {
                            if (card.kind === "file") section.open(card.modelData.file.path);
                            else if (card.kind === "media") Hub.media("play-pause");
                            else if (card.kind === "game") section.launchGame(card.modelData.game);
                            else section.resume(card.modelData.device);
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: card.kind + ": " + (card.kind === "file" ? card.modelData.file.title : card.kind === "game" ? card.modelData.game.title : "")
                }
            }
        }
    }
}
