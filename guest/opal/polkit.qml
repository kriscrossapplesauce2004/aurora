import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    PolkitDialog { id: agent; standalone: true }
    IpcHandler {
        target: "polkit"
        function status(): string { return agent.registered ? "registered" : "unregistered"; }
    }
    Timer {
        interval: 10000; running: true
        onTriggered: if (!agent.registered) { console.error("Opal polkit agent could not register"); Qt.exit(1); }
    }
}
