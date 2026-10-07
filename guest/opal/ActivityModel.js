.pragma library

// Pure activity model. No Quickshell, Hub or DBus access, so Node can test it.
// An activity is a plain object: {id, kind, title, subtitle, icon, progress, priority, since, until, controls, nid}.

var MAX_ACTIVITIES = 6;
var CHARGE_SHOW_MS = 10000;
var LINK_SHOW_MS = 8000;
var DONE_SHOW_MS = 4000;
var LOW_BATTERY = 20;

// Higher priority wins the compact slot. Calls and recordings stay above everything.
var PRIORITY = {call: 90, recording: 85, transfer: 70, focus: 60, media: 50, charging: 30, connectivity: 20};

function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
function text(value) { return value === undefined || value === null ? "" : String(value); }

// Progress is 0 to 1, or -1 when the value is unknown.
function progressFromValue(value) {
    var number = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
    if (typeof number !== "number" || !isFinite(number)) return -1;
    return clamp(number, 0, 100) / 100;
}

function categoryOf(note) {
    var hints = note.hints || {};
    return text(note.category || hints.category).toLowerCase();
}

// Turn one notification description into an activity, or null when it is a plain message.
function fromNotification(note, now) {
    if (!note || note.id === undefined || note.id === null) return null;
    var hints = note.hints || {};
    var category = categoryOf(note);
    var progress = progressFromValue(hints.value !== undefined ? hints.value : note.value);
    var name = text(note.appName);
    var isCall = /^(call|x-.*call)/.test(category) || /\.call(\.|$)/.test(category);
    var isRecording = /record|screencast/.test(category) || (/(record|screencast|obs|kooha)/i.test(name) && !!note.resident);
    var isTransfer = /^(transfer|network\.transfer|x-.*(progress|transfer))/.test(category) || category === "progress" || progress >= 0;
    // A finished transfer is a normal message. Only an unfinished one stays here.
    if (/complete|error|done|finished/.test(category)) return null;
    var kind = isCall ? "call" : isRecording ? "recording" : isTransfer ? "transfer" : "";
    if (kind === "") return null;
    // A transient message without progress is not an ongoing activity.
    if (note.transient && progress < 0 && kind === "transfer") return null;
    var done = kind === "transfer" && progress >= 1;
    var icon = kind === "call" ? "call" : kind === "recording" ? "fiber_manual_record" : done ? "download_done" : "download";
    var actions = (note.actions || []).filter(function (a) { return a.identifier !== "default"; }).slice(0, 2);
    var subtitle = text(note.body).split("\n")[0].slice(0, 80);
    if (!subtitle) subtitle = name;
    var received = typeof note.received === "number" ? note.received : now;
    return {
        id: "n:" + note.id, nid: note.id, kind: kind, icon: icon,
        title: text(note.summary) || name || "Activity",
        subtitle: subtitle, app: name, progress: kind === "transfer" ? progress : -1,
        priority: PRIORITY[kind], since: received, until: done ? received + DONE_SHOW_MS : 0,
        controls: actions.map(function (a, i) { return {id: "note-action", index: i, label: text(a.text)}; })
    };
}

function formatClock(seconds) {
    var s = Math.max(0, Math.floor(seconds));
    var m = Math.floor(s / 60);
    return m + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
}

// Build every local-signal activity. The signals object holds plain values only.
function fromSignals(sig, now) {
    var out = [];
    var media = sig.media || {};
    if (text(media.track) !== "") {
        out.push({
            id: "media", kind: "media", icon: "music", art: text(media.art),
            title: text(media.track), subtitle: text(media.artist) || (media.playing ? "Playing" : "Paused"),
            progress: -1, priority: PRIORITY.media - (media.playing ? 0 : 8), since: sig.mediaSince || now, until: 0,
            playing: !!media.playing,
            controls: [{id: "media-previous", icon: "previous"}, {id: media.playing ? "media-pause" : "media-play", icon: media.playing ? "pause" : "play"}, {id: "media-next", icon: "skip"}]
        });
    }
    var focus = sig.focus || {};
    if (focus.running) {
        var total = focus.total > 0 ? focus.total : 1500;
        out.push({
            id: "focus", kind: "focus", icon: "timer", title: formatClock(focus.seconds), subtitle: "Focus session",
            progress: clamp(1 - focus.seconds / total, 0, 1), priority: PRIORITY.focus, since: sig.focusSince || now, until: 0,
            controls: [{id: "focus-toggle", icon: "pause"}, {id: "focus-stop", icon: "close"}]
        });
    }
    var battery = sig.battery || {};
    if (battery.percent >= 0 && battery.charging) {
        var recent = battery.changedAt > 0 && now - battery.changedAt < CHARGE_SHOW_MS;
        if (recent || (battery.percent <= LOW_BATTERY && battery.percent < 100)) {
            out.push({
                id: "charging", kind: "charging", icon: "charging", title: "Charging " + Math.round(battery.percent) + "%",
                subtitle: battery.percent >= 100 ? "Fully charged" : "Plugged in", progress: clamp(battery.percent / 100, 0, 1),
                priority: PRIORITY.charging, since: battery.changedAt || now, until: recent ? battery.changedAt + CHARGE_SHOW_MS : 0, controls: []
            });
        }
    }
    var net = sig.network || {};
    if (net.changedAt > 0 && now - net.changedAt < LINK_SHOW_MS) {
        out.push({
            id: "connectivity", kind: "connectivity", icon: net.wifi ? "wifi" : "wifiOff",
            title: net.wifi ? "Connected" : "Offline", subtitle: net.wifi ? text(net.name) : "No network",
            progress: -1, priority: PRIORITY.connectivity, since: net.changedAt, until: net.changedAt + LINK_SHOW_MS, controls: []
        });
    }
    (sig.notifications || []).forEach(function (note) {
        var activity = fromNotification(note, now);
        if (activity) out.push(activity);
    });
    if (sig.recording && !out.some(function (a) { return a.kind === "recording"; })) {
        out.push({id: "recording", kind: "recording", icon: "fiber_manual_record", title: "Screen recording", subtitle: "Recording", progress: -1,
            priority: PRIORITY.recording, since: sig.recordingSince || now, until: 0, controls: []});
    }
    return out;
}

function rank(list) {
    return list.slice().sort(function (a, b) {
        if (b.priority !== a.priority) return b.priority - a.priority;
        if (b.since !== a.since) return b.since - a.since;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
}

// Merge new activities into the previous list. Same id replaces in place and keeps its first-seen time.
function merge(previous, incoming, now) {
    var seen = {};
    (previous || []).forEach(function (a) { seen[a.id] = a; });
    var byId = {};
    incoming.forEach(function (a) {
        if (a.until > 0 && a.until <= now) return;
        var old = seen[a.id];
        byId[a.id] = Object.assign({}, a, {since: old ? old.since : a.since});
    });
    var merged = Object.keys(byId).map(function (id) { return byId[id]; });
    return rank(merged).slice(0, MAX_ACTIVITIES);
}

// Short text for the compact pill: primary activity and how many more wait behind it.
function summary(list) {
    if (!list.length) return {primary: null, extra: 0, label: ""};
    var primary = list[0];
    var extra = list.length - 1;
    var label = primary.title + (extra > 0 ? ", plus " + extra + " more" : "");
    return {primary: primary, extra: extra, label: label};
}

// Find 4 to 8 digit codes. Years, times, decimals and long numbers are not codes.
var CONTEXT = /(code|otp|pin|passcode|password|verification|verify|token|security|one[- ]?time|2fa|login|sign[- ]?in|kode|c[oó]digo)/i;
function findCodes(body) {
    var s = text(body);
    if (s.length > 2000) s = s.slice(0, 2000);
    var re = /(^|[^\d.,:\/])(\d{3}[ -]\d{3}|\d{4,8})(?![\d]|[.,:\/-]\d)/g;
    var hasContext = CONTEXT.test(s);
    var found = [];
    var m;
    while ((m = re.exec(s)) !== null) {
        var raw = m[2];
        var digits = raw.replace(/[ -]/g, "");
        if (digits.length < 4 || digits.length > 8) continue;
        var isYear = digits.length === 4 && /^(19|20)\d\d$/.test(digits);
        if (isYear && !hasContext) continue;
        // Without a context word, only accept a code that stands alone in a short message.
        if (!hasContext && s.length > 60) continue;
        if (found.indexOf(digits) < 0) found.push(digits);
    }
    // A year next to a real code is not the code.
    var plain = found.filter(function (d) { return !/^(19|20)\d\d$/.test(d); });
    return plain.length ? plain : found;
}

// Suggestion chips. Local signals only, hidden during DND, never more than three.
function suggestions(sig, dismissed) {
    if (!sig || sig.dnd) return [];
    var skip = {};
    (dismissed || []).forEach(function (id) { skip[id] = true; });
    var out = [];
    if (sig.dock && sig.dock.name && !sig.dock.handled) {
        out.push({id: "dock:" + sig.dock.name, kind: "dock", label: "Use as desktop", detail: sig.dock.name, icon: "desktop", arg: sig.dock.name, priority: 80});
    }
    (sig.codes || []).forEach(function (c) {
        var codes = findCodes(c.body);
        if (codes.length) out.push({id: "code:" + c.id + ":" + codes[0], kind: "code", label: "Copy code " + codes[0], detail: text(c.app), icon: "copy", arg: codes[0], priority: 90});
    });
    (sig.sessions || []).forEach(function (s) {
        if (!s || !s.app) return;
        out.push({id: "continue:" + s.device + ":" + s.app, kind: "continue", label: "Continue " + (s.appName || s.app), detail: text(s.deviceName), icon: "link", arg: s.app, priority: 60});
    });
    var b = sig.battery || {};
    if (b.percent >= 0 && b.percent <= LOW_BATTERY && !b.charging && !b.saver && b.canSave) {
        out.push({id: "saver", kind: "saver", label: "Battery saver", detail: Math.round(b.percent) + "%", icon: "battery", arg: "", priority: 70});
    }
    out = out.filter(function (s) { return !skip[s.id]; });
    out.sort(function (a, b2) { return b2.priority - a.priority || (a.id < b2.id ? -1 : 1); });
    return out.slice(0, 3);
}
