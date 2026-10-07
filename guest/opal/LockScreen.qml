import QtQuick
import Quickshell
import Quickshell.Wayland

// Session lock. Each output gets a lock surface; PAM decides when to unlock.
Scope {
    LockController { id: lock; onUnlocked: Hub.locked = false }
    WlSessionLock {
        id: session
        locked: Hub.locked
        WlSessionLockSurface {
            color: Theme.base
            LockScene {
                anchors.fill: parent
                mode: "lock"
                userName: Quickshell.env("OPAL_USER_NAME") || lock.login
                avatar: Quickshell.env("HOME") ? "file://" + Quickshell.env("HOME") + "/.face" : ""
                error: lock.error
                busy: lock.busy
                prompt: lock.pamResponseRequired && lock.pamMessage ? lock.pamMessage : "Password"
                echo: lock.pamResponseRequired && lock.pamResponseVisible
                notificationGroups: lock.notificationGroups
                onSubmitted: response => lock.submit(response)
                onPowerRequested: verb => Hub.command({action: "power", verb: verb})
            }
        }
    }
}
