import QtQuick
import Quickshell

// Background services: schedules (night light, dark mode, Do not disturb) and app theme export.
Scope {
    id: services
    function minutes(text) { const p = (text || "00:00").split(":"); return parseInt(p[0]) * 60 + parseInt(p[1]); }
    // True when now is inside [from, to), also across midnight.
    function inside(from, to) {
        const now = Hub.now.getHours() * 60 + Hub.now.getMinutes(), a = minutes(from), b = minutes(to);
        return a <= b ? now >= a && now < b : now >= a || now < b;
    }
    function window(item, fallbackFrom, fallbackTo) {
        return item.mode === "sun" ? [Hub.sun.sunset, Hub.sun.sunrise] : [item.from || fallbackFrom, item.to || fallbackTo];
    }
    // Schedules act on transitions, so a manual change holds until the next edge.
    property var last: ({})
    function evaluate() {
        if (!Hub.preferencesLoaded) return;
        const all = Hub.prefs.schedules || {};
        const next = {};
        const night = all.nightLight || {};
        const nightOn = !!night.enabled && inside.apply(null, window(night, "21:00", "07:00"));
        if (last.night !== nightOn || last.temperature !== (night.temperature || 4000)) Hub.command({action: "night-light", enabled: nightOn, temperature: night.temperature || 4000});
        next.night = nightOn; next.temperature = night.temperature || 4000;
        const dark = all.darkMode || {};
        if (dark.enabled) {
            const darkOn = inside.apply(null, window(dark, "19:00", "07:00"));
            if (last.dark !== darkOn && Theme.light === darkOn) Hub.set("light", !darkOn);
            next.dark = darkOn;
        }
        const quiet = all.dnd || {};
        if (quiet.enabled) {
            const quietOn = inside.apply(null, window(quiet, "23:00", "07:00"));
            if (last.quiet !== quietOn && Hub.dnd !== quietOn) Hub.set("dnd", quietOn);
            next.quiet = quietOn;
        }
        last = next;
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: services.evaluate() }
    Connections { target: Hub; function onPrefsChanged() { evaluateSoon.restart(); exportSoon.restart(); } }
    Timer { id: evaluateSoon; interval: 400; onTriggered: services.evaluate() }
    // Sun times once at start and then every six hours.
    Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: Hub.command({action: "sun-times"}) }

    // App theme export, after the palette settles.
    function hex(c) { const v = Qt.color(c); const h = x => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, "0"); return "#" + h(v.r) + h(v.g) + h(v.b); }
    readonly property var colors: ({primary: hex(Theme.primary), onPrimary: hex(Theme.onPrimary), primaryContainer: hex(Theme.primaryContainer), onPrimaryContainer: hex(Theme.onContainer),
        secondary: hex(Theme.secondary), tertiary: hex(Theme.tertiary), base: hex(Theme.base), surface: hex(Theme.surface), surfaceHigh: hex(Theme.surfaceHigh),
        text: hex(Theme.text), subtext: hex(Theme.subtext), error: hex(Theme.error)})
    readonly property var exportOptions: ({light: Theme.light, font: Theme.font})
    property string exported: ""
    onColorsChanged: exportSoon.restart()
    Connections { target: Hub; function onPrefsChanged() { exportSoon.restart(); } }
    Timer {
        id: exportSoon; interval: 1500
        onTriggered: {
            const targets = Hub.prefs.themeExport || [];
            if (!Hub.preferencesLoaded || !targets.length) return;
            const signature = JSON.stringify([services.colors, targets, services.exportOptions, Hub.prefs.themeSync]);
            if (signature === services.exported) return;
            services.exported = signature;
            Hub.command({action: "theme-export", colors: services.colors, targets: targets, options: services.exportOptions});
        }
    }
}
