.pragma library

function normalize(value) {
    return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
}

function oneEdit(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
        if (a[i] === b[j]) { i++; j++; continue; }
        if (++edits > 1) return false;
        if (a.length >= b.length) i++;
        if (b.length >= a.length) j++;
    }
    return edits + (i < a.length || j < b.length ? 1 : 0) <= 1;
}

function score(title, metadata, query) {
    var name = normalize(title), hay = normalize(metadata), q = normalize(query).slice(0, 128);
    if (!q) return 0;
    if (name === q) return 1200;
    if (name.startsWith(q)) return 1000;
    if (name.indexOf(q) >= 0) return 850;
    var words = name.split(/[^a-z0-9\u0080-\uffff]+/).filter(Boolean);
    if (q.length > 1 && words.map(function(w) { return w[0]; }).join("") === q) return 780;
    var tokens = q.split(" ").slice(0, 8), total = 0;
    for (var t = 0; t < tokens.length; t++) {
        var token = tokens[t], value = -1;
        if (words.some(function(w) { return w === token; })) value = 740;
        else if (words.some(function(w) { return w.startsWith(token); })) value = 680;
        else if (name.indexOf(token) >= 0) value = 580;
        else if (hay.indexOf(token) >= 0) value = 440;
        else if (token.length >= 4 && words.some(function(w) { return oneEdit(w, token); })) value = 300;
        else if (token.length >= 3) {
            var at = 0;
            for (var n = 0; n < name.length && at < token.length; n++) if (name[n] === token[at]) at++;
            if (at === token.length) value = Math.max(80, 180 - name.length);
        }
        if (value < 0) return -1;
        total += value;
    }
    return total / tokens.length;
}

function search(query, scope, apps, windows, actions, pins, recent) {
    var q = String(query || "").trim(), kind = scope || "all", results = [];
    if (q[0] === ">") { kind = "action"; q = q.slice(1).trim(); }
    if (q[0] === "@") { kind = "window"; q = q.slice(1).trim(); }
    function add(type, title, detail, icon, data, key, metadata, boost) {
        var rank = score(title, metadata, q);
        if (rank >= 0) results.push({kind:type, title:title, detail:detail, icon:icon, data:data, key:key, score:rank + boost});
    }
    if (kind === "all" || kind === "app") (apps || []).forEach(function(record) {
        var app = record.app, recentIndex = (recent || []).indexOf(app.id);
        add("app", app.name, app.genericName || "Application", app.icon, app, "app:" + app.id, record.hay,
            ((pins || []).indexOf(app.id) >= 0 ? 18 : 0) + (recentIndex >= 0 ? Math.max(0, 12 - recentIndex) : 0));
    });
    if (kind === "all" || kind === "window") (windows || []).forEach(function(win, index) {
        add("window", win.title || win.className, win.className + (win.workspace ? " · Workspace " + win.workspace : ""), "", win,
            "window:" + (win.address || index), win.className, 10);
    });
    if (kind === "all" || kind === "action") (actions || []).forEach(function(action) {
        add("action", action.name, action.detail, action.icon, action, "action:" + action.id, action.keywords, -20);
    });
    results.sort(function(a, b) { return b.score - a.score || a.title.localeCompare(b.title) || a.key.localeCompare(b.key); });
    return results.slice(0, 60);
}
