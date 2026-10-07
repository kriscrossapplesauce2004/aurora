import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// Greeter logic: users, sessions and the greetd conversation. The view is in greeter.qml.
Scope {
    id: root
    // Test hook: the adapter command can point at fixture data.
    property var infoCommand: ["python3", Qt.resolvedUrl("greeter_info.py").toString().replace("file://", "")]
    property bool launched: false
    property var users: []
    property var sessions: []
    property string layout: ""
    property int userIndex: 0
    property int sessionIndex: 0
    property string error: ""
    property bool busy: false
    property string pending: ""
    property string prompt: "Password"
    property bool echo: false
    property bool responseRequired: true
    readonly property var user: users[userIndex] || ({login: "", name: ""})
    readonly property var session: sessions[sessionIndex] || null
    readonly property var whatsNew: [
        {icon: "view_column", title: "A calmer bar", text: "Fewer, bolder islands. Choose islands, dock, split or edge in Settings."},
        {icon: "bolt", title: "Live activity", text: "Music and focus timers sit in the bar. Volume and workspace changes show there too."},
        {icon: "notifications", title: "Better notifications", text: "Smaller popups, and an inbox grouped by app inside the control sheet."},
        {icon: "tune", title: "Your control sheet", text: "Reorder sections and add a calendar, system monitor, clipboard or battery list."},
        {icon: "apps", title: "New Start", text: "Categories on the left, a bold clock up top, and three icon styles."},
        {icon: "lock", title: "Opal lock screen", text: "This login screen and the lock screen now share one design."}
    ]
    Component.onCompleted: info.running = true

    // Users, sessions and the last choice come from a small adapter.
    Process {
        id: info
        command: root.infoCommand
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.users = data.users || [];
                    root.sessions = data.sessions || [];
                    root.layout = data.layout || "";
                    const last = data.last || {};
                    root.userIndex = Math.max(0, root.users.findIndex(u => u.login === last.user));
                    const preferred = root.sessions.findIndex(s => s.id === last.session);
                    root.sessionIndex = preferred >= 0 ? preferred : Math.max(0, root.sessions.findIndex(s => s.id === "hyprland"));
                } catch (error) { root.error = "Couldn't read users and sessions."; }
            }
        }
    }
    Process { id: rememberer }

    function submit(text) {
        if (busy || !user.login) return;
        if (!Greetd.available) { error = "The login service isn't running."; return; }
        error = "";
        pending = text;
        busy = true;
        if (Greetd.state === GreetdState.Inactive) Greetd.createSession(user.login);
        else if (responseRequired) { Greetd.respond(pending); pending = ""; }
    }
    function pickUser(index) {
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        userIndex = index; error = ""; busy = false; pending = "";
    }
    Connections {
        target: Greetd
        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            root.prompt = message || "Password";
            root.echo = echoResponse;
            root.responseRequired = responseRequired;
            if (isError) root.error = message;
            if (responseRequired) {
                if (root.pending !== "") { Greetd.respond(root.pending); root.pending = ""; }
                else root.busy = false;
            } else Greetd.respond("");
        }
        function onAuthFailure(message) {
            root.busy = false; root.pending = ""; root.prompt = "Password"; root.echo = false;
            root.error = message && message !== "authentication failed" ? message : "That password didn't work. Try again.";
            Greetd.cancelSession();
        }
        function onReadyToLaunch() {
            if (!root.session) { root.error = "Choose a session first."; root.busy = false; Greetd.cancelSession(); return; }
            rememberer.command = root.infoCommand.concat(["--remember", root.user.login, root.session.id]);
            rememberer.running = true;
            Greetd.launch(root.session.command, ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + root.session.id, "XDG_CURRENT_DESKTOP=" + (root.session.desktop || root.session.id)]);
        }
        function onLaunched() { root.launched = true; }
        function onError(message) { root.busy = false; root.pending = ""; root.error = message; }
    }
    Process {
        id: powerProcess
        function run(verb) { command = ["systemctl", verb === "poweroff" ? "poweroff" : verb === "reboot" ? "reboot" : "suspend"]; running = true; }
    }
    function power(verb) { powerProcess.run(verb); }
}
