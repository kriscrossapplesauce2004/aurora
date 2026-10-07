import QtQuick
import Quickshell
import Quickshell.Services.Pam

// Lock logic: PAM conversation and notification counts. The surfaces are in LockScreen.qml.
Scope {
    id: lock
    signal unlocked()
    readonly property alias pamMessage: pam.message
    readonly property alias pamResponseRequired: pam.responseRequired
    readonly property alias pamResponseVisible: pam.responseVisible
    property string error: ""
    property bool busy: false
    property string pending: ""
    readonly property string login: Quickshell.env("USER") || ""
    readonly property var notificationGroups: {
        const revision = Notifier.revision;
        const map = {};
        Notifier.inbox.forEach(e => {
            const app = e.notification.appName || "App";
            if (!map[app]) map[app] = {app: app, icon: e.notification.appIcon || "", count: 0};
            map[app].count++;
        });
        return Object.keys(map).map(k => map[k]).sort((a, b) => b.count - a.count);
    }
    function submit(text) {
        if (busy) return;
        error = "";
        pending = text;
        busy = true;
        if (!pam.active) pam.start();
        // A prompt may already be waiting, so no change signal will arrive.
        if (pam.active && pam.responseRequired && pending !== "") { pam.respond(pending); pending = ""; }
    }
    PamContext {
        id: pam
        // Tests point these at a throwaway PAM directory.
        configDirectory: Quickshell.env("OPAL_PAM_DIR") || "/etc/pam.d"
        config: Quickshell.env("OPAL_PAM_CONFIG") || "login"
        user: lock.login
        // A second prompt (for example a one-time code) waits for new input.
        onResponseRequiredChanged: if (responseRequired) { if (lock.pending !== "") { respond(lock.pending); lock.pending = ""; } else lock.busy = false; }
        onCompleted: result => {
            errorFallback.stop();
            lock.busy = false;
            lock.pending = "";
            if (result === PamResult.Success) { lock.error = ""; lock.unlocked(); }
            else lock.error = pam.messageIsError && pam.message ? pam.message : "That password didn't work. Try again.";
        }
        // Completion normally follows an error and sets the message; this is the fallback.
        onError: error => errorFallback.restart()
    }
    Timer { id: errorFallback; interval: 300; onTriggered: { lock.busy = false; lock.pending = ""; lock.error = "Couldn't check your password. Try again."; } }
}
