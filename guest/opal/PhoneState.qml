pragma Singleton
import QtQuick
import Quickshell

// Shared phone and tablet state: gestures, split view, pen, torch, battery and task-aware data.
Scope {
    id: s
    // Backend data.
    property var activity: ({files: [], games: []})
    property var torch: ({available: false, on: false})
    property var battery: ({available: false})
    property var batteryHistory: []
    // A wide phone output is a tablet when its shorter side is at least 600 logical pixels.
    function isTablet(screen) { return !!screen && Math.min(screen.width, screen.height) >= 600 && Hub.layoutFor(screen.width, screen.height, screen.name) === "phone"; }
    function phoneScreens() { return Quickshell.screens.filter(sc => Hub.layoutFor(sc.width, sc.height, sc.name) === "phone"); }
    // Icon grid metrics shared by home, drawer and folders, so every icon grid has the same rhythm.
    function columnsFor(width, wide) {
        const forced = Hub.prefs.phoneRows;
        if (forced) return Math.max(4, Math.min(forced, Math.floor((width - 8) / 64)));
        return wide ? 6 : width >= 400 ? 5 : 4;
    }
    function iconSize(cellWidth) { return Math.round(Math.max(48, Math.min(64, cellWidth - 22))); }
    function cellHeight(cellWidth) { return iconSize(cellWidth) + 38; }
    readonly property int navHeight: Hub.prefs.phoneButtons ? 64 : 48
    readonly property int barHeight: 48

    // Pen awareness: after a stylus touch, targets grow and nothing depends on hover.
    property bool pen: false
    readonly property int hit: pen ? 56 : 48
    function penSeen() { pen = true; penReset.restart(); }
    function touchSeen() { if (pen) penReset.restart(); }
    Timer { id: penReset; interval: 120000; onTriggered: s.pen = false }

    // Recent windows, newest first, so back and app switching follow what the user did.
    property var mru: []
    readonly property string activeAddress: (Hub.status && Hub.status.activeAddress) || ""
    onActiveAddressChanged: if (activeAddress !== "") mru = [activeAddress].concat(mru.filter(a => a !== activeAddress)).slice(0, 12)
    function windowByAddress(address) { return Hub.windows.find(w => w.address === address) || null; }
    function activeWindow() { return Hub.windows.find(w => Hub.active(w)) || null; }
    function previousWindow() {
        for (let i = 0; i < mru.length; i += 1) {
            const w = windowByAddress(mru[i]);
            if (w && !Hub.active(w)) return w;
        }
        return Hub.windows.find(w => !Hub.active(w)) || null;
    }
    function neighbour(step) {
        const list = Hub.windows;
        if (list.length < 2) return null;
        const index = Math.max(0, list.findIndex(w => Hub.active(w)));
        return list[(index + step + list.length) % list.length];
    }
    readonly property bool appInFront: Hub.windows.some(w => Hub.active(w))
    readonly property bool atHome: Hub.page === "launcher" ? Hub.mobileTab === "home" : Hub.page === "" && !(Hub.status.hypr && appInFront)

    // Finger-tracking gestures. The navigation pill and the edge zones drive these.
    property string phase: ""
    property string outcome: ""
    property real progress: 0
    property real dx: 0
    property real dy: 0
    property int edge: 0
    property var gestureScreen: null
    property real velocityX: 0
    property real velocityY: 0
    signal drawerReleased(bool open)
    function begin(screen) { holdTimer.stop(); outcome = ""; phase = ""; progress = 0; dx = 0; dy = 0; edge = 0; gestureScreen = screen; }
    function height_() { return gestureScreen ? gestureScreen.height : 800; }
    function width_() { return gestureScreen ? gestureScreen.width : 400; }
    // Called while the finger moves. Offsets are from the touch-down point; velocities are in pixels per second.
    function move(offsetX, offsetY, vx, vy) {
        dx = offsetX; dy = offsetY; velocityX = vx; velocityY = vy;
        if (phase === "" && (Math.abs(offsetX) > 12 || Math.abs(offsetY) > 12)) {
            if (Math.abs(offsetY) >= Math.abs(offsetX)) {
                if (offsetY < 0) phase = atHome ? "drawer" : "home";
            } else if (!atHome && Hub.windows.length > 1) phase = "switch";
        }
        if (phase === "drawer") progress = Math.min(1, Math.max(0, -offsetY / (height_() * .55)));
        else if (phase === "home" || phase === "recents") {
            progress = Math.min(1, Math.max(0, -offsetY / (height_() * .5)));
            // Slow and high: hold to reach recents. Moving again returns to the home gesture.
            if (phase === "home" && progress > .2 && Math.abs(vy) < 160) holdTimer.start();
            else if (phase === "home" || Math.abs(vy) > 320) { holdTimer.stop(); if (phase === "recents") phase = "home"; }
        }
    }
    Timer { id: holdTimer; interval: 340; onTriggered: if (s.phase === "home") s.phase = "recents" }
    // Called when the finger lifts. Returns after it starts the action; the overlay then plays the settle.
    function end() {
        holdTimer.stop();
        const flingUp = velocityY < -700;
        if (phase === "drawer") {
            const open = progress > .28 || velocityY < -600;
            drawerReleased(open);
            phase = ""; progress = 0;
            return;
        }
        if (phase === "recents") { outcome = "recents"; openRecents(); }
        else if (phase === "home") {
            if (progress > .28 || flingUp) { outcome = "home"; goHome(); } else outcome = "cancel";
        } else if (phase === "switch") {
            const w = width_();
            if (Math.abs(dx) > w * .3 || Math.abs(velocityX) > 650) { outcome = "switch"; switchApp(dx > 0 ? -1 : 1); } else outcome = "cancel";
        } else { phase = ""; return; }
        if (Theme.motion(1) === 0) finish();
    }
    function finish() { phase = ""; outcome = ""; progress = 0; dx = 0; dy = 0; edge = 0; }
    function cancel() { holdTimer.stop(); if (phase === "drawer") drawerReleased(false); outcome = "cancel"; if (Theme.motion(1) === 0 || phase === "") finish(); }

    // Edge back swipe from the left or right edge.
    function beginEdge(screen, side) { begin(screen); phase = "back"; edge = side; }
    function moveEdge(offset) { dx = offset; progress = Math.min(1, Math.max(0, Math.abs(offset) / 96)); }
    function endEdge() {
        if (progress >= 1) { outcome = "back"; back(); } else outcome = "cancel";
        if (Theme.motion(1) === 0) finish();
    }

    // Actions. They only change shell state or ask the compositor adapter. They never send keys to apps.
    function goHome() {
        Hub.query = ""; Hub.mobileTab = "home"; Hub.close();
        if (Hub.status.hypr) Hub.command({action: "phone-home"});
    }
    function openRecents() { if (gestureScreen) Hub.targetScreen = gestureScreen; Hub.mobileTab = "recent"; Hub.page = "launcher"; }
    function switchApp(step) {
        const w = step < 0 ? previousWindow() : neighbour(step);
        if (w) Hub.focusWindow(w);
    }
    // Back closes one shell layer. With an app in front it returns to the previous app, as apps own their keys.
    function back() {
        if (Hub.page === "settings" && Hub.settingsSection !== "") Hub.settingsSection = "";
        else if (Hub.controlDetail !== "" && (Hub.page === "controls" || Hub.page === "notifications")) Hub.controlDetail = "";
        else if (Hub.page === "launcher" && Hub.mobileTab !== "home") { Hub.mobileTab = "home"; }
        else if (Hub.page !== "") Hub.close();
        else { const w = previousWindow(); if (w) Hub.focusWindow(w); }
    }

    // Split view and slide-over on tablets through the optional compositor adapter.
    property bool splitActive: false
    property string splitLeft: ""
    property string splitRight: ""
    property real splitRatio: Hub.prefs.phoneSplitRatio || .5
    property var splitScreen: null
    property string slideAddress: ""
    function outputName(screen) { return screen ? screen.name : ""; }
    function keyboardInset(screen) { return Hub.systemOskVisible && screen ? Math.round(screen.height * .38) : 0; }
    function applySplit() {
        if (!splitActive || !splitScreen) return;
        Hub.command({action: "phone-split", output: splitScreen.name, left: splitLeft, right: splitRight, ratio: splitRatio, top: barHeight, bottom: navFor(splitScreen), keyboard: keyboardInset(splitScreen), workspace: Number(Hub.status.workspace) || 0});
    }
    // The tablet dock is inside the navigation bar now, so there is no extra dock height.
    function dockHeight(screen) { return 0; }
    function navFor(screen) { return isTablet(screen) && Hub.prefs.tabletDock !== false ? 68 : navHeight; }
    function startSplit(screen, left, right) {
        if (!left || !right || left === right || !Hub.status.hypr) return false;
        splitScreen = screen; splitLeft = left; splitRight = right; splitActive = true;
        applySplit();
        splitCheck.restart();
        return true;
    }
    function splitWithPrevious(screen) {
        const a = activeWindow(), b = previousWindow();
        return a && b ? startSplit(screen, a.address, b.address) : false;
    }
    function setRatio(value, commit) {
        splitRatio = Math.max(.25, Math.min(.75, value));
        if (commit) { Hub.set("phoneSplitRatio", splitRatio); applySplit(); } else splitThrottle.start();
    }
    Timer { id: splitThrottle; interval: 70; onTriggered: s.applySplit() }
    // A split that did not take hold (windows not floating side by side) ends, so no divider is left over an app.
    Timer {
        id: splitCheck; interval: 1500
        onTriggered: {
            if (!s.splitActive) return;
            const ws = Hub.compositorWindows.filter(w => w.address === s.splitLeft || w.address === s.splitRight);
            const placed = ws.length === 2 && ws.every(w => w.floating) && ws[0].workspace === ws[1].workspace;
            if (!placed) { s.endSplit(); Hub.message("Split view could not place both windows"); }
        }
    }
    function endSplit() {
        if (!splitActive) return;
        Hub.command({action: "phone-unsplit", addresses: [splitLeft, splitRight], outputs: phoneScreens().map(sc => sc.name)});
        splitActive = false; splitLeft = ""; splitRight = "";
    }
    function slideOver(screen, address) {
        if (!address || !Hub.status.hypr) return;
        slideAddress = address;
        Hub.command({action: "phone-slideover", output: screen.name, address: address, fraction: .38, top: barHeight, bottom: navFor(screen)});
    }
    // A split ends when one of its windows closes.
    readonly property var windowAddresses: Hub.windows.map(w => w.address)
    onWindowAddressesChanged: if (splitActive && (windowAddresses.indexOf(splitLeft) < 0 || windowAddresses.indexOf(splitRight) < 0)) { splitActive = false; splitLeft = ""; splitRight = ""; }

    // Fit apps to phone outputs. A window that opens, or an output that changes, triggers one debounced call.
    function fit() {
        // While a split is shown the fitter waits; maximizing would break the split.
        if (!Hub.status.hypr || Hub.prefs.phoneFitApps === false || splitActive) return;
        const names = phoneScreens().map(sc => sc.name);
        if (names.length) Hub.command({action: "phone-fit", outputs: names, modes: Hub.prefs.phoneAppModes || ({})});
    }
    Timer { id: fitTimer; interval: 350; onTriggered: s.fit() }
    // When an output stops being a phone, windows that phone mode floated or maximized get their own state back.
    property var lastPhoneNames: []
    readonly property var phoneNames: phoneScreens().map(sc => sc.name)
    onPhoneNamesChanged: {
        const left = lastPhoneNames.filter(n => phoneNames.indexOf(n) < 0);
        lastPhoneNames = phoneNames.slice();
        if (left.length && Hub.status.hypr) { if (splitActive) endSplit(); Hub.command({action: "phone-release", outputs: []}); }
    }
    Connections { target: Hub; function onCompositorWindowsChanged() { fitTimer.restart(); } }
    // The on-screen keyboard lifts floating windows. Tiled windows resize by the compositor.
    Connections {
        target: Hub
        function onSystemOskVisibleChanged() { liftTimer.restart(); }
    }
    Timer {
        id: liftTimer; interval: 200
        onTriggered: s.phoneScreens().forEach(sc => Hub.command({action: "phone-lift", output: sc.name, keyboard: s.keyboardInset(sc)}))
    }

    // Backend events.
    function ingest(e) {
        if (e.event === "recentActivity") activity = {files: e.files || [], games: e.games || []};
        else if (e.event === "torch") torch = {available: !!e.available, on: !!e.on, name: e.name || ""};
        else if (e.event === "batteryStats") {
            battery = e;
            if (e.available && e.percent !== null) batteryHistory = batteryHistory.concat([{t: Date.now(), percent: e.percent, watts: e.watts || 0}]).slice(-120);
        }
    }
    function refreshActivity() { Hub.command({action: "recent-activity"}); }
    function refreshTorch() { Hub.command({action: "torch-status"}); }
    function setTorch(on) { Hub.command({action: "torch", on: on}); }
    function refreshBattery() { Hub.command({action: "battery-stats"}); }
    Component.onCompleted: refreshTorch()
}
