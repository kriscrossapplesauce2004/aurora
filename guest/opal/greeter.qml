import QtQuick
import Quickshell
import Quickshell.Wayland

// Opal greeter entry point for greetd. Run with OPAL_GREETER=1 so Hub skips the session backend.
ShellRoot {
    GreeterController { id: root; onLaunchedChanged: if (launched) Qt.quit() }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "opal-greeter"
            // Only the first output takes the keyboard.
            WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: Theme.base
            LockScene {
                anchors.fill: parent
                mode: "greeter"
                focus: true
                userName: root.user.name || root.user.login
                avatar: root.user.avatar || ""
                users: root.users
                userIndex: root.userIndex
                sessions: root.sessions
                sessionIndex: root.sessionIndex
                keyboardLayout: root.layout.toUpperCase()
                whatsNew: root.whatsNew
                prompt: root.prompt
                echo: root.echo
                error: root.error
                busy: root.busy
                onSubmitted: response => root.submit(response)
                onUserPicked: index => root.pickUser(index)
                onSessionPicked: index => root.sessionIndex = index
                onPowerRequested: verb => root.power(verb)
            }
        }
    }
}
