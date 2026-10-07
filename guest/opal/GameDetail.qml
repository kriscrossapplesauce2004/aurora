import QtQuick
import QtQuick.Layouts

// Game detail sheet: art, local playtime and actions. Controller first.
Item {
    id: sheet
    // Library entry from ConsoleHome: {kind, id, title, cover, hero, source, lastPlayed, data}.
    property var entry: null
    property bool running: false
    property bool pinned: false
    property bool open: false
    property bool confirmUninstall: false
    property bool confirmQuit: false
    readonly property var facts: entry && GameState.detail.id === entry.id ? GameState.detail : ({})
    signal play()
    signal pin()
    signal quit()
    signal uninstall()
    signal dismissed()

    function minutesText(m) { return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"; }
    function sizeText(bytes) { return bytes >= 1073741824 ? (bytes / 1073741824).toFixed(1) + " GB" : Math.max(1, Math.round(bytes / 1048576)) + " MB"; }
    function ago(stamp) {
        if (!stamp) return "Never";
        const days = Math.floor((Date.now() / 1000 - stamp) / 86400);
        return days < 1 ? "Today" : days === 1 ? "Yesterday" : days < 30 ? days + " days ago" : Qt.formatDate(new Date(stamp * 1000), "d MMM yyyy");
    }
    onOpenChanged: { confirmUninstall = false; confirmQuit = false; }
    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.motion(Theme.durMedium) } }

    Rectangle { anchors.fill: parent; color: Theme.alpha("#000000", .55); MouseArea { anchors.fill: parent; onClicked: sheet.dismissed() } }
    Rectangle {
        id: card
        width: Math.min(820, sheet.width - 48)
        height: Math.min(560, sheet.height - 140)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -28
        radius: Theme.shapeXl
        color: Theme.level(2)
        border.width: 1; border.color: Theme.outline
        scale: sheet.open ? 1 : .94
        Behavior on scale { NumberAnimation { duration: Theme.motion(Theme.durLong); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate } }
        MouseArea { anchors.fill: parent }
        RowLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 24
            // Portrait art.
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Math.min(220, card.width * .28); Layout.maximumWidth: Layout.preferredWidth; Layout.fillWidth: false
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: width * 1.5
                    radius: Theme.shapeLg; color: Theme.primaryContainer
                    RoundedImage { anchors.fill: parent; radius: Theme.shapeLg; source: sheet.entry ? sheet.entry.cover || sheet.entry.hero || "" : ""; decodeSize: Qt.size(440, 660) }
                    Glyph { visible: !!sheet.entry && !sheet.entry.cover && !sheet.entry.hero; anchors.centerIn: parent; name: "sports_esports"; font.pixelSize: 56; color: Theme.onContainer }
                }
                Item { Layout.fillHeight: true }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                MText { Layout.fillWidth: true; text: sheet.entry ? sheet.entry.title : ""; role: "displayS"; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                GridLayout {
                    Layout.fillWidth: true; columns: 2; rowSpacing: 8; columnSpacing: 8
                    Repeater {
                        model: [
                            {icon: "sports_esports", label: "Source", value: sheet.entry ? sheet.entry.source : ""},
                            {icon: "schedule", label: "Playtime", value: sheet.facts.playtimeMinutes !== undefined && sheet.facts.playtimeMinutes !== null ? sheet.minutesText(sheet.facts.playtimeMinutes) : "Not tracked"},
                            {icon: "history", label: "Last played", value: sheet.ago(sheet.facts.lastPlayed || (sheet.entry ? sheet.entry.lastPlayed : 0))},
                            {icon: "hard_drive", label: "Size", value: sheet.facts.sizeBytes ? sheet.sizeText(sheet.facts.sizeBytes) : "Unknown"}
                        ]
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 58; radius: Theme.shapeMd; color: Theme.level(3)
                            Column {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                                spacing: 2
                                MText { width: parent.width; text: modelData.label; role: "labelS"; color: Theme.subtext }
                                MText { width: parent.width; text: modelData.value; role: "titleS"; font.features: {"tnum": 1} }
                            }
                        }
                    }
                }
                Item { Layout.preferredHeight: 2 }
                QaRow {
                    Layout.fillWidth: true
                    icon: "play_arrow"; title: sheet.running ? "Resume" : "Play"; detail: sheet.running ? "Switch to the running game" : "Start from " + (sheet.entry ? sheet.entry.source : "the library")
                    onActivated: sheet.play()
                }
                QaRow {
                    Layout.fillWidth: true
                    icon: "keep"; title: sheet.pinned ? "Unpin from favourites" : "Pin to favourites"
                    onActivated: sheet.pin()
                }
                QaRow {
                    visible: sheet.running; Layout.fillWidth: true
                    danger: true; icon: "close"
                    title: sheet.confirmQuit ? "Press " + ControllerNav.acceptLabel + " again to quit" : "Quit game"
                    onActivated: { if (!sheet.confirmQuit) { sheet.confirmQuit = true; return; } sheet.confirmQuit = false; sheet.quit(); }
                }
                QaRow {
                    visible: !!sheet.facts.uninstallable; Layout.fillWidth: true
                    danger: true; icon: "delete"
                    title: sheet.confirmUninstall ? "Press " + ControllerNav.acceptLabel + " again to open Steam uninstall" : "Uninstall"
                    detail: sheet.confirmUninstall ? "Steam asks for its own confirmation" : "Uses Steam"
                    onActivated: { if (!sheet.confirmUninstall) { sheet.confirmUninstall = true; return; } sheet.confirmUninstall = false; sheet.uninstall(); }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
    ControllerFocus {
        anchors.fill: parent
        root: card; priority: 8; closeOnBack: false
        active: sheet.open
        onBack: sheet.dismissed()
    }
}
