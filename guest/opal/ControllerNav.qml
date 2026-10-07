pragma Singleton
import QtQuick

// Routes controller events to the one Opal surface that owns them. A game never loses input to Opal.
QtObject {
    id: nav
    // Surfaces that own the controller now, ordered by priority. The last one wins.
    property var claims: []
    // True after a controller press, false after pointer movement. Focus rings and hints follow it.
    property bool usingController: false
    readonly property var top: claims.length ? claims[claims.length - 1] : null
    readonly property bool nintendo: Hub.prefs.controllerLayout === "nintendo"
    readonly property string acceptLabel: nintendo ? "B" : "A"
    readonly property string backLabel: nintendo ? "A" : "B"
    readonly property string altLabel: nintendo ? "Y" : "X"
    readonly property string searchLabel: nintendo ? "X" : "Y"
    signal key(string name)

    function claim(surface) {
        const list = claims.filter(c => c && c !== surface);
        list.push(surface);
        // The sort is stable, so a later claim wins among equal priorities.
        list.sort((a, b) => a.priority - b.priority);
        claims = list;
    }
    function release(surface) { claims = claims.filter(c => c && c !== surface); }

    // Guide opens Quick Access. Console mode with no game running keeps its launcher toggle.
    function guide(force) {
        usingController = true;
        if (GameState.quickAccess) { GameState.closeQuickAccess(); return; }
        if (Hub.locked) return;
        // Steam also reacts to Guide. This setting lets Steam keep it.
        if (Hub.prefs.quickAccessGuide === false && force !== true) return;
        if (force !== true && Hub.prefs.mode === "console" && !GameState.gameActive) { Hub.toggle("launcher"); return; }
        GameState.openQuickAccess(false);
    }
    // Every backend navigation event enters here. With nothing open the event is ignored.
    function input(name) {
        if (name === "home" || name === "guide") { guide(); return; }
        // Guide plus A always opens Quick Access, even when Guide alone is off.
        if (name === "guide+accept") { guide(true); return; }
        // Holding Guide opens the Claude assistant.
        if (name === "guideHold") { if (!Hub.locked && Hub.page !== "assistant") { usingController = true; Hub.openAssistant(); } return; }
        if (top) { usingController = true; key(name); return; }
        // The console library page keeps its own navigation.
        if (Hub.prefs.mode === "console" && Hub.page === "launcher") Hub.navigate(name);
    }
    // Keyboard keys on a surface with focus map to the same names.
    function fromKeyboard(event) {
        const map = {};
        map[Qt.Key_Up] = "up"; map[Qt.Key_Down] = "down"; map[Qt.Key_Left] = "left"; map[Qt.Key_Right] = "right";
        map[Qt.Key_Return] = "accept"; map[Qt.Key_Enter] = "accept"; map[Qt.Key_Escape] = "back";
        map[Qt.Key_PageUp] = "previousTab"; map[Qt.Key_PageDown] = "nextTab"; map[Qt.Key_Backtab] = "previousTab";
        map[Qt.Key_Tab] = "nextTab"; map[Qt.Key_Delete] = "pin";
        const name = map[event.key];
        if (!name || !top) return false;
        usingController = true;
        key(name);
        return true;
    }
}
