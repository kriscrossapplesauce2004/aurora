pragma Singleton
import QtQuick
import Quickshell
import "ActivityModel.js" as Model

// Live activities and suggestion chips. Plain data only: notification objects stay owned by Notifier.
Scope {
    id: root
    // Tests set these to show fixed data without services.
    property var fixture: null
    property var chipFixture: null
    property var list: []
    property var ids: []
    property var byId: ({})
    property var chips: []
    property var dismissed: []
    property double chargeChanged: 0
    property double netChanged: 0
    property double mediaSince: 0
    property double focusSince: 0
    property bool lastCharging: false
    property bool lastWifi: true
    property bool primed: false
    readonly property double startedAt: Date.now()
    readonly property var primary: list.length ? list[0] : null
    readonly property int count: list.length
    readonly property var summary: Model.summary(list)

    function nowMs() { return Hub.now.getTime(); }
    function notes() {
        const rev = Notifier.revision;
        return Notifier.entries.filter(e => e.notification && !e.notification.lastGeneration).map(e => {
            const n = e.notification;
            return {id: n.id, appName: n.appName, summary: n.summary, body: n.body, resident: n.resident, transient: n.transient,
                hints: n.hints || {}, received: e.received,
                actions: n.actions.map(a => ({identifier: a.identifier, text: a.text}))};
        });
    }
    function signals(withNotes) {
        const s = Hub.status;
        return {
            media: {track: s.track, artist: s.artist, art: s.art, playing: s.playing}, mediaSince: mediaSince,
            focus: {running: Hub.focusRunning, seconds: Hub.focusSeconds, total: 1500}, focusSince: focusSince,
            battery: {percent: s.battery, charging: s.charging, changedAt: chargeChanged},
            network: {wifi: s.wifi, name: s.network, changedAt: netChanged},
            notifications: withNotes ? notes() : []
        };
    }
    function privacyAllows() { const p = Hub.prefs.lockNotifications || "title"; return p !== "off" && p !== "count"; }
    function refresh() {
        const now = nowMs();
        const s = Hub.status;
        // The first seconds after start only settle the state. They are not changes.
        if (primed && now - startedAt > 6000) {
            if (!!s.charging !== lastCharging) chargeChanged = now;
            if (!!s.wifi !== lastWifi) netChanged = now;
        }
        lastCharging = !!s.charging; lastWifi = !!s.wifi; primed = true;
        if (s.track === "") mediaSince = 0; else if (mediaSince === 0) mediaSince = now;
        if (!Hub.focusRunning) focusSince = 0; else if (focusSince === 0) focusSince = now;
        const next = fixture !== null ? Model.merge([], fixture, now) : Model.merge(list, Model.fromSignals(signals(true), now), now);
        const nextIds = next.map(a => a.id);
        const map = {};
        next.forEach(a => { map[a.id] = a; });
        byId = map;
        if (JSON.stringify(nextIds) !== JSON.stringify(ids)) ids = nextIds;
        list = next;
        const nextChips = chipFixture !== null ? chipFixture : Model.suggestions(chipSignals(), dismissed);
        if (JSON.stringify(nextChips) !== JSON.stringify(chips)) chips = nextChips;
    }
    function chipSignals() {
        const sessions = (Hub.linkDevices || []).filter(d => d.opal && d.reachable && d.session && d.session.app).map(d => {
            const app = Hub.appForClass(d.session.app);
            return app ? {device: d.id, deviceName: d.name, app: d.session.app, appName: app.name} : null;
        }).filter(x => x);
        const dock = Hub.dockScreen ? {name: Hub.dockScreen.name, handled: !!Hub.dockResult || !!Hub.sessionModes[Hub.dockScreen.name]} : null;
        const s = Hub.status;
        // Codes come from unread popups and the inbox. The text is read here and not kept.
        const codes = Notifier.inbox.filter(e => !e.read || e.popup).slice(0, 5).map(e => ({id: e.notification.id, app: e.notification.appName, body: e.notification.body + " " + e.notification.summary}));
        return {dnd: Hub.dnd, dock: dock, sessions: sessions, codes: codes,
            battery: {percent: s.battery, charging: s.charging, saver: s.profile === "power-saver", canSave: !!s.profile}};
    }
    function dismissChip(chip) { dismissed = dismissed.concat([chip.id]).slice(-30); refresh(); }
    function runChip(chip) {
        if (chip.kind === "dock" && typeof Hub.dockAs === "function") Hub.dockAs("desktop");
        else if (chip.kind === "continue") { const app = Hub.appForClass(chip.arg); if (app) Hub.launch(app); }
        else if (chip.kind === "code") { Hub.command({action: "clipboard", text: chip.arg}); Hub.message("Code copied"); }
        else if (chip.kind === "saver") Hub.command({action: "profile", value: "power-saver"});
        dismissChip(chip);
    }
    function entryFor(nid) { return Notifier.entries.find(e => e.notification && e.notification.id === nid) || null; }
    function control(activity, ctl) {
        switch (ctl.id) {
        case "media-previous": Hub.media("previous"); break;
        case "media-next": Hub.media("next"); break;
        case "media-play": case "media-pause": Hub.media("play-pause"); break;
        case "focus-toggle": Hub.timerToggle(); break;
        case "focus-stop": Hub.focusRunning = false; Hub.focusSeconds = 25 * 60; break;
        case "note-action": {
            const e = entryFor(activity.nid);
            const action = e ? e.notification.actions.filter(a => a.identifier !== "default")[ctl.index] : null;
            if (action) action.invoke();
            break;
        }
        }
        refresh();
    }
    function open(activity, output) {
        if (activity.kind === "media") Hub.toggleAudio(output);
        else if (activity.nid !== undefined) {
            const e = entryFor(activity.nid);
            const action = e ? e.notification.actions.find(a => a.identifier === "default") : null;
            if (action) action.invoke(); else { Hub.targetScreen = output; Hub.toggle("notifications"); }
        } else { Hub.targetScreen = output; Hub.toggle("controls"); }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Connections { target: Notifier; function onRevisionChanged() { Qt.callLater(root.refresh); } }
    Connections { target: Hub; function onStatusChanged() { Qt.callLater(root.refresh); } }
}
