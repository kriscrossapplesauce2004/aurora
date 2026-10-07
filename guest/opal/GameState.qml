pragma Singleton
import QtQuick

// Quick Access state: the overlay, the running game and the performance report from game_perf.py.
QtObject {
    id: state
    property bool quickAccess: false
    // True when the overlay was opened by keyboard or IPC, so it may take keyboard focus.
    property bool keyboardOpened: false
    property var perf: ({})
    property var detail: ({})
    readonly property bool perfReady: perf.event === "gamePerf"
    // A library game with a window, else the fullscreen window title.
    readonly property var runningGame: Hub.games.find(g => Hub.gameRunning(g)) || null
    readonly property bool fullscreen: (Hub.status.fullscreenMonitors || []).length > 0
    readonly property bool gameActive: runningGame !== null || fullscreen
    readonly property string gameTitle: runningGame ? runningGame.title : fullscreen ? (Hub.status.title || "Current app") : ""
    readonly property var gameWindows: runningGame ? Hub.gameWindows(runningGame) : []
    // Time since Opal first saw this game running.
    property string seenId: ""
    property date seenAt: new Date()
    readonly property int sessionMinutes: gameActive ? Math.max(0, Math.floor((Hub.now - seenAt) / 60000)) : 0
    onGameTitleChanged: { if (gameTitle !== "" && gameTitle !== seenId) seenAt = new Date(); seenId = gameTitle; }

    function receive(e) {
        if (e.event === "gamePerf") perf = e;
        else if (e.event === "gameDetail") detail = e;
    }
    function refresh() { Hub.command({action: "perf-get"}); }
    function set(key, value) { Hub.command({action: "perf-set", key: key, value: value}); }
    function loadDetail(id) { detail = {id: id}; Hub.command({action: "game-detail", id: id}); }
    function openQuickAccess(keyboard) {
        Hub.close();
        Hub.targetScreen = Hub.chooseScreen();
        keyboardOpened = keyboard === true;
        quickAccess = true;
        refresh();
    }
    function closeQuickAccess() { quickAccess = false; }
    function toggleQuickAccess() { if (quickAccess) closeQuickAccess(); else openQuickAccess(true); }
    function quitGame() { gameWindows.forEach(w => Hub.closeWindow(w)); }
}
