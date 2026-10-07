import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit

Scope {
    id: root
    property bool standalone: false
    readonly property bool registered: agentLoader.item ? agentLoader.item.registered : false
    FileView {
        id: externalAgent
        path: root.standalone ? "" : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/opal/polkit-standalone"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    Loader {
        id: agentLoader
        active: root.standalone || externalAgent.text().trim() !== "1"
        sourceComponent: Scope {
            readonly property bool registered: agent.isRegistered
            PolkitAgent { id: agent }
            LazyLoader {
                active: agent.isActive && agent.flow !== null
                PanelWindow {
                    id: window
                    screen: Hub.chooseScreen()
                    anchors { top: true; bottom: true; left: true; right: true }
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "opal-polkit"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                    color: Theme.alpha("#000000", .42)
                    MouseArea { anchors.fill: parent }
                    Flickable {
                        anchors.fill: parent; anchors.margins: 16
                        contentHeight: Math.max(height, card.height + 32)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        PolkitCard {
                            id: card
                            width: Math.min(456, parent.width)
                            x: (parent.width - width) / 2
                            y: Math.max(16, (window.height - 32 - height) / 2)
                            flow: agent.flow
                        }
                    }
                    // Controller: move between the password, reveal, cancel and authenticate controls.
                    ControllerFocus {
                        anchors.fill: parent; root: card; priority: 30; closeOnBack: false; preferText: true
                        onBack: card.cancel()
                    }
                }
            }
        }
    }
}
