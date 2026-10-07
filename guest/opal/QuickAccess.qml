import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Quick Access: a floating sheet over the running game with game, performance, quick settings and notifications. Controller first.
Item {
    id: qa
    property int tabIndex: 0
    property real reveal: GameState.quickAccess ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: Theme.motion(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecelerate } }
    readonly property bool shown: GameState.quickAccess || reveal > .001
    readonly property var perf: GameState.perf
    readonly property var tabs: [{name: "Game", icon: "sports_esports"}, {name: "Performance", icon: "speed"}, {name: "Quick", icon: "tune"}, {name: "Alerts", icon: "notifications"}]
    readonly property real sheetWidth: Math.min(Math.max(520, Math.min(640, width * .3)), width - 24)
    readonly property var fpsChoices: [0, 30, 40, 45, 60, 72, 90, 120, 144]
    readonly property var overlayChoices: [{id: "off", name: "Off"}, {id: "fps", name: "FPS only"}, {id: "compact", name: "Compact"}, {id: "full", name: "Full"}]
    readonly property var profileNames: ({"power-saver": "Saver", "balanced": "Balanced", "performance": "Performance"})
    readonly property var profileIcons: ({"power-saver": "eco", "balanced": "balance", "performance": "rocket_launch"})
    property bool confirmQuit: false

    function step(delta) {
        tabIndex = (tabIndex + delta + tabs.length) % tabs.length;
        if (ControllerNav.usingController) padFocus.selectSoon();
    }
    function cycle(list, current, delta) {
        const i = Math.max(0, list.indexOf(current));
        return list[(i + delta + list.length) % list.length];
    }
    function fpsLabel(v) { return v === 0 ? "Off" : v + " FPS"; }
    function minutesText(m) { return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min"; }
    function leave() { GameState.closeQuickAccess(); }
    onShownChanged: { if (shown) { tabIndex = 0; confirmQuit = false; } }

    focus: GameState.quickAccess
    Keys.onPressed: e => { if (ControllerNav.fromKeyboard(e)) e.accepted = true; }
    // Perf data refreshes while the sheet is open, for controller batteries and GameMode.
    Timer { interval: 5000; repeat: true; running: GameState.quickAccess; onTriggered: GameState.refresh() }
    Timer { id: quitReset; interval: 4000; onTriggered: qa.confirmQuit = false }
    Timer { id: tdpDelay; property int watts: 0; interval: 220; onTriggered: GameState.set("tdp", watts) }

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha("#000000", .5 * qa.reveal)
        MouseArea { anchors.fill: parent; enabled: GameState.quickAccess; onClicked: qa.leave() }
    }
    Rectangle {
        id: sheet
        width: qa.sheetWidth
        y: 12; height: qa.height - 24
        x: qa.width - width - 12 + (width + 24) * (1 - qa.reveal)
        radius: Theme.shapeXl
        color: Theme.alpha(Theme.level(2), .985)
        border.width: 1; border.color: Theme.outline
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors { fill: parent; margins: 20; topMargin: 22 }
            spacing: 14
            // Header: title, controller batteries, clock.
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20; color: Theme.primaryContainer
                    Glyph { anchors.centerIn: parent; name: "sports_esports"; font.pixelSize: 22; color: Theme.onContainer }
                }
                MText { text: "Quick access"; role: "title"; font.pixelSize: 22; Layout.fillWidth: true }
                Repeater {
                    model: (qa.perf.controllers || []).slice(0, 3)
                    Rectangle {
                        required property var modelData
                        readonly property bool low: modelData.percent <= 15 && !modelData.charging
                        Layout.preferredHeight: 30; Layout.preferredWidth: batteryRow.implicitWidth + 20; radius: 15
                        color: low ? Theme.alpha(Theme.error, .18) : Theme.level(4)
                        Row {
                            id: batteryRow
                            anchors.centerIn: parent; spacing: 5
                            Glyph { name: modelData.charging ? "charging" : "gamepad"; font.pixelSize: 17; color: parent.parent.low ? Theme.error : Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            MText { text: modelData.percent + "%"; role: "labelS"; font.weight: Font.Bold; font.features: {"tnum": 1}; color: parent.parent.low ? Theme.error : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Accessible.name: modelData.name + " " + modelData.percent + " percent"
                    }
                }
                Row {
                    spacing: 4
                    Glyph { visible: Hub.status.battery >= 0; name: Hub.status.charging ? "charging" : "battery"; font.pixelSize: 18; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                    MText { visible: Hub.status.battery >= 0; text: Hub.status.battery + "%"; role: "label"; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                    MText { text: Qt.formatDateTime(Hub.now, "HH:mm"); role: "title"; font.features: {"tnum": 1}; leftPadding: 6; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            // Section tabs.
            Row {
                Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: qa.tabs
                    Rectangle {
                        id: tabChip
                        required property var modelData
                        required property int index
                        readonly property bool current: qa.tabIndex === index
                        height: 40; width: current ? tabContent.implicitWidth + 32 : 44; radius: 20
                        color: current ? Theme.secondaryContainer : "transparent"
                        Behavior on width { NumberAnimation { duration: Theme.motion(Theme.durMedium); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasized } }
                        Behavior on color { ColorAnimation { duration: Theme.motion(Theme.durShort) } }
                        clip: true
                        Row {
                            id: tabContent
                            anchors.verticalCenter: parent.verticalCenter; x: tabChip.current ? 16 : 10; spacing: 8
                            Glyph { name: tabChip.modelData.icon; font.pixelSize: 22; color: tabChip.current ? Theme.onSecondaryContainer : Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                            MText { visible: tabChip.current; text: tabChip.modelData.name; role: "label"; font.weight: Font.Bold; color: Theme.onSecondaryContainer; anchors.verticalCenter: parent.verticalCenter }
                        }
                        // Unread notifications mark the Alerts tab.
                        Rectangle { visible: tabChip.modelData.name === "Alerts" && Hub.unread > 0 && !tabChip.current; x: 28; y: 6; width: 9; height: 9; radius: 5; color: Theme.error }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: qa.tabIndex = tabChip.index }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.name
                    }
                }
            }
            // Section content.
            Item {
                id: contentArea
                Layout.fillWidth: true; Layout.fillHeight: true
                Flickable {
                    id: flick
                    anchors.fill: parent
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width; contentHeight: pageLoader.height
                    ScrollBar.vertical: ScrollBar {}
                    Loader {
                        id: pageLoader
                        width: flick.width
                        active: qa.shown
                        sourceComponent: qa.tabIndex === 0 ? gameTab : qa.tabIndex === 1 ? performanceTab : qa.tabIndex === 2 ? quickTab : alertsTab
                    }
                }
                // Soft fade where rows scroll under the footer.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 18; visible: flick.contentHeight > flick.height + 1
                    gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Theme.alpha(Theme.level(2), .985) } }
                }
            }
            // Hints.
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ControllerHints {
                    items: {
                        const list = [{b: ControllerNav.acceptLabel, t: "Select"}, {b: ControllerNav.backLabel, t: "Close"}, {b: "LB RB", t: "Section"}];
                        if (qa.tabIndex === 3) list.push({b: ControllerNav.altLabel, t: "Dismiss"});
                        return list;
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    ControllerFocus {
        id: padFocus
        anchors.fill: parent
        root: contentArea
        priority: 10
        active: GameState.quickAccess
        closeOnBack: false
        showHints: false
        onBack: qa.leave()
        onTab: delta => qa.step(delta)
    }

    // Game: the running game, or recent games.
    Component {
        id: gameTab
        ColumnLayout {
            spacing: 8
            Rectangle {
                id: hero
                Layout.fillWidth: true; Layout.preferredHeight: Math.round(width * .5)
                radius: Theme.shapeLg
                color: GameState.runningGame ? Theme.primaryContainer : Theme.level(3)
                RoundedImage {
                    anchors.fill: parent
                    radius: hero.radius
                    source: GameState.runningGame ? (GameState.runningGame.hero || GameState.runningGame.cover || "") : ""
                }
                Rectangle {
                    anchors.fill: parent; radius: hero.radius
                    visible: GameState.gameActive
                    gradient: Gradient { GradientStop { position: .35; color: "transparent" } GradientStop { position: 1; color: Theme.alpha("#000000", .72) } }
                }
                Column {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
                    spacing: 3
                    Glyph { visible: !GameState.gameActive; anchors.horizontalCenter: parent.horizontalCenter; name: "sports_esports"; font.pixelSize: 40; color: Theme.muted }
                    MText {
                        width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2
                        horizontalAlignment: GameState.gameActive ? Text.AlignLeft : Text.AlignHCenter
                        text: GameState.gameActive ? GameState.gameTitle : "No game is running"
                        role: "title"; font.pixelSize: 24; color: GameState.gameActive ? "#ffffff" : Theme.text
                    }
                    MText {
                        width: parent.width
                        horizontalAlignment: GameState.gameActive ? Text.AlignLeft : Text.AlignHCenter
                        text: GameState.gameActive ? "Playing for " + qa.minutesText(GameState.sessionMinutes) + (GameState.runningGame ? "  ·  " + GameState.runningGame.source : "") : "Launch one from the library"
                        role: "label"; color: GameState.gameActive ? Theme.alpha("#ffffff", .85) : Theme.subtext
                    }
                }
            }
            Item { Layout.preferredHeight: 4; visible: GameState.gameActive }
            // Game actions as tiles, in the shade's tile style.
            GridLayout {
                visible: GameState.gameActive; Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 64; dense: true
                    icon: "play_arrow"; title: "Return to game"; subtitle: "Close this panel"; active: true
                    onToggled: clicked(0, 0)
                    onClicked: { const w = GameState.gameWindows[0]; qa.leave(); if (w) Hub.focusWindow(w); }
                }
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 64; dense: true
                    icon: "select_window"; title: "Switch app"; subtitle: Hub.windows.length + " windows open"
                    onToggled: clicked(0, 0)
                    onClicked: { qa.leave(); Hub.targetScreen = Hub.chooseScreen(); Hub.page = "windows"; }
                }
                ShadeTile {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 64; dense: true
                    icon: "screenshot_monitor"; title: "Screenshot"; subtitle: "Saved to Pictures"
                    onToggled: clicked(0, 0)
                    onClicked: { qa.leave(); Hub.command({action: "screenshot"}); }
                }
                ShadeTile {
                    visible: GameState.gameWindows.length > 0
                    Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 64; dense: true
                    icon: "close"; title: qa.confirmQuit ? "Press " + ControllerNav.acceptLabel + " again" : "Quit game"
                    subtitle: qa.confirmQuit ? "Unsaved progress is lost" : "Ends the game"; active: qa.confirmQuit
                    onToggled: clicked(0, 0)
                    onClicked: {
                        if (!qa.confirmQuit) { qa.confirmQuit = true; quitReset.restart(); return; }
                        qa.confirmQuit = false; GameState.quitGame(); qa.leave();
                    }
                }
            }
            MText {
                visible: !GameState.gameActive && Hub.games.some(g => g.lastPlayed > 0)
                text: "Recently played"; role: "titleS"; Layout.leftMargin: 6; Layout.topMargin: 6; color: Theme.subtext
            }
            Repeater {
                model: GameState.gameActive ? [] : Hub.games.filter(g => g.lastPlayed > 0).slice(0, 5)
                QaRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "play_arrow"; title: modelData.title; detail: modelData.source + "  ·  " + Qt.formatDate(new Date(modelData.lastPlayed * 1000), "d MMM")
                    onActivated: { qa.leave(); Hub.launchGame(modelData); }
                }
            }
        }
    }

    // Performance: frame cap, overlay, GameMode, power profile and optional TDP.
    Component {
        id: performanceTab
        ColumnLayout {
            spacing: 8
            QaRow {
                visible: !GameState.perfReady; Layout.fillWidth: true
                kind: "info"; icon: "hourglass_empty"; title: "Reading performance state"
            }
            // Each choice is a row of chips, so every option is visible and one press away.
            ChoiceGroup {
                visible: GameState.perfReady; Layout.fillWidth: true
                icon: "speed"; title: "Frame limit"; detail: "MangoHud"
                options: qa.fpsChoices.map(v => ({id: v, name: v === 0 ? "Off" : String(v)}))
                current: qa.perf.fpsLimit || 0
                onPicked: id => GameState.set("fpsLimit", id)
            }
            ChoiceGroup {
                visible: GameState.perfReady; Layout.fillWidth: true
                icon: "monitoring"; title: "Performance overlay"; detail: qa.perf.mangohud ? "MangoHud" : "MangoHud is not installed"
                options: qa.overlayChoices; current: qa.perf.overlay || "compact"
                onPicked: id => GameState.set("overlay", id)
            }
            ChoiceGroup {
                visible: GameState.perfReady && !!qa.perf.profiles && qa.perf.profiles.available; Layout.fillWidth: true
                icon: qa.profileIcons[Hub.status.profile || "balanced"] || "balance"; title: "Power profile"; detail: "powerprofilesctl"
                options: (qa.perf.profiles && qa.perf.profiles.profiles || []).map(id => ({id: id, name: qa.profileNames[id] || id, icon: qa.profileIcons[id] || ""}))
                current: Hub.status.profile || "balanced"
                onPicked: id => Hub.command({action: "profile", value: id})
            }
            QaRow {
                visible: GameState.perfReady && !!qa.perf.tdp; Layout.fillWidth: true
                kind: "slider"; icon: "bolt"; title: "Power limit"; unit: " W"; pressSteps: 1
                from: qa.perf.tdp ? qa.perf.tdp.min : 0; to: qa.perf.tdp ? qa.perf.tdp.max : 100; value: qa.perf.tdp ? qa.perf.tdp.watts : 0
                onSliderMoved: v => { tdpDelay.watts = Math.round(v); tdpDelay.restart(); }
            }
            ChoiceGroup {
                visible: GameState.perfReady && !!qa.perf.gpu; Layout.fillWidth: true
                icon: "memory"; title: "GPU performance"; detail: "Performance level"
                options: [{id: "auto", name: "Auto"}, {id: "low", name: "Low"}, {id: "high", name: "High"}]
                current: qa.perf.gpu ? qa.perf.gpu.level : "auto"
                onPicked: id => GameState.set("gpuLevel", id)
            }
            QaRow {
                visible: GameState.perfReady; Layout.fillWidth: true
                kind: "info"; icon: "sports_esports"; title: "GameMode"
                detail: qa.perf.gamemode && qa.perf.gamemode.active ? qa.perf.gamemode.clients + (qa.perf.gamemode.clients === 1 ? " game" : " games") + " tuned" : ""
                choice: !qa.perf.gamemode || !qa.perf.gamemode.available ? "Not installed" : qa.perf.gamemode.active ? "Active" : "Idle"
            }
            QaRow {
                visible: GameState.perfReady; Layout.fillWidth: true
                icon: "content_copy"; title: "Copy Steam launch option"; detail: "Steam games read the frame limit through it"
                onActivated: Hub.command({action: "perf-copy"})
            }
        }
    }

    // Quick settings.
    Component {
        id: quickTab
        ColumnLayout {
            spacing: 8
            QaRow {
                visible: Hub.status.brightness >= 0; Layout.fillWidth: true
                kind: "slider"; icon: "sun"; title: "Brightness"; value: Hub.status.brightness
                onSliderMoved: v => Hub.command({action: "brightness", value: Math.round(v)})
            }
            QaRow {
                Layout.fillWidth: true
                kind: "slider"; icon: Hub.status.muted ? "mute" : "volume"; title: "Volume"; value: Hub.status.muted ? 0 : Hub.status.volume
                onSliderMoved: v => Hub.volume(v)
                onAlternate: Hub.command({action: "mute"})
            }
            // Toggles in the shade's tile style.
            GridLayout {
                Layout.fillWidth: true; Layout.topMargin: 4; columns: 2; columnSpacing: 8; rowSpacing: 8
                Repeater {
                    model: [
                        {id: "wifi", icon: "wifi", title: "Wi-Fi", sub: Hub.status.wifi ? Hub.status.network || "On" : "Off", on: !!Hub.status.wifi},
                        {id: "bluetooth", icon: "bluetooth", title: "Bluetooth", sub: Hub.status.bluetooth ? "On" : "Off", on: !!Hub.status.bluetooth},
                        {id: "quiet", icon: "timer", title: "Quiet session", sub: "No popups, no sleep", on: Hub.gameSession},
                        {id: "dnd", icon: "do_not_disturb_on", title: "Do not disturb", sub: Hub.dnd ? "On" : "Off", on: Hub.dnd}
                    ]
                    ShadeTile {
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 64; dense: true
                        icon: modelData.icon; title: modelData.title; subtitle: modelData.sub; active: modelData.on
                        onClicked: toggled()
                        onToggled: {
                            if (modelData.id === "wifi") Hub.connection("wifi", "power", {enabled: !(Hub.connectivity.wifi.powered || Hub.status.wifi)});
                            else if (modelData.id === "bluetooth") Hub.connection("bluetooth", "power", {enabled: !(Hub.connectivity.bluetooth.powered || Hub.status.bluetooth)});
                            else if (modelData.id === "quiet") Hub.toggleGameSession();
                            else Hub.set("dnd", !Hub.dnd);
                        }
                    }
                }
            }
            QaRow {
                Layout.fillWidth: true
                kind: "toggle"; icon: "gamepad"; title: "Guide button opens this"; detail: "Tap: Quick Access. Hold: Claude. Guide+A: always. Turn off if Steam uses Guide"; checked: Hub.prefs.quickAccessGuide !== false
                onActivated: Hub.set("quickAccessGuide", Hub.prefs.quickAccessGuide === false)
            }
            QaRow {
                Layout.fillWidth: true
                icon: "settings"; title: "Opal settings"
                onActivated: { qa.leave(); Hub.targetScreen = Hub.chooseScreen(); Hub.openSettings(); }
            }
        }
    }

    // Notifications from the shell inbox.
    Component {
        id: alertsTab
        ColumnLayout {
            spacing: 8
            QaRow {
                visible: Notifier.inbox.length > 0; Layout.fillWidth: true
                icon: "clear_all"; title: "Clear all"; detail: Notifier.inbox.length + (Notifier.inbox.length === 1 ? " notification" : " notifications")
                onActivated: Notifier.clear()
            }
            Repeater {
                model: Notifier.inbox.slice(0, 20)
                QaRow {
                    id: alert
                    required property var modelData
                    readonly property var notice: modelData.notification
                    Layout.fillWidth: true
                    icon: "notifications"
                    title: notice ? notice.summary || notice.appName : ""
                    detail: notice ? (notice.appName ? notice.appName + "  ·  " : "") + (notice.body || "").replace(/\s+/g, " ").slice(0, 70) + "  ·  " + Notifier.age(modelData.received) : ""
                    onActivated: {
                        const action = notice ? notice.actions.find(a => a.identifier === "default") : null;
                        if (action) { action.invoke(); qa.leave(); }
                        else Notifier.dismiss(modelData);
                    }
                    onAlternate: Notifier.dismiss(modelData)
                }
            }
            Column {
                visible: Notifier.inbox.length === 0
                Layout.fillWidth: true; Layout.topMargin: 40; spacing: 10
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: Hub.dnd ? "do_not_disturb_on" : "notifications"; font.pixelSize: 44; color: Theme.muted }
                MText { anchors.horizontalCenter: parent.horizontalCenter; text: Hub.dnd ? "Nothing new. Do not disturb is on." : "Nothing new"; role: "title"; color: Theme.subtext }
            }
        }
    }
}
