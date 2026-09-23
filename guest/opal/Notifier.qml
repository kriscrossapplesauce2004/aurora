pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Scope {
    id: service
    // Live protocol objects stay owned by the server. Entries own presentation
    // state only; closing an object removes every reference before it is freed.
    property var entries: []
    readonly property var inbox: entries.filter(e => e.notification && !e.notification.transient)
    readonly property int unread: inbox.filter(e => !e.read).length
    readonly property var popups: entries.filter(e => e.popup).slice(0, 3)
    property bool centerOpen: false
    property bool dnd: Hub.prefs.dnd === true || Hub.gameSession
    property var popupScreen: null
    property int revision: 0
    function refresh() { entries = entries.slice(); revision++; }
    function age(time) {
        const minutes = Math.max(0, Math.floor((Hub.now.getTime() - time) / 60000));
        return minutes < 1 ? "Now" : minutes < 60 ? minutes + "m" : minutes < 1440 ? Math.floor(minutes / 60) + "h" : Qt.formatDateTime(new Date(time), "d MMM");
    }
    function markAllRead() { entries.forEach(e => e.read = true); refresh(); }
    function hidePopup(entry) {
        if (!entry || !entry.notification) return;
        entry.popup = false;
        if (entry.notification.transient) entry.notification.expire();
        else refresh();
    }
    function dismiss(entry) { if (entry && entry.notification) entry.notification.dismiss(); }
    function clear() { inbox.slice().forEach(dismiss); }
    function remove(entry) {
        entries = entries.filter(e => e !== entry);
        entry.notification = null;
        entry.destroy();
    }
    function present(entry) {
        if (!entry.notification) return;
        entry.received = Date.now();
        entry.read = centerOpen;
        entry.remaining = entry.notification.urgency === NotificationUrgency.Critical || entry.notification.expireTimeout === 0
            ? -1 : entry.notification.expireTimeout < 0 ? 6500 : Math.max(1000, entry.notification.expireTimeout);
        entry.popup = !dnd && !centerOpen && !entry.notification.lastGeneration;
        if (entry.popup && !popups.length) popupScreen = Hub.chooseScreen();
        entries = [entry].concat(entries.filter(e => e !== entry));
        // Bound bursts without losing the inbox. Excess transient items expire.
        entries.filter(e => e.popup).slice(8).forEach(hidePopup);
        inbox.slice(100).forEach(dismiss);
        if (!entry.popup && entry.notification && entry.notification.transient)
            Qt.callLater(() => { if (entry.notification) entry.notification.expire(); });
    }
    onCenterOpenChanged: if (centerOpen) {
        entries.slice().forEach(e => { if (e.popup) hidePopup(e); });
        markAllRead();
    }
    onDndChanged: if (dnd) entries.slice().forEach(e => { if (e.popup) hidePopup(e); });

    Component {
        id: entryComponent
        QtObject {
            id: entry
            property var notification: null
            property double received: Date.now()
            property bool read: false
            property bool popup: false
            property bool hovered: false
            property real remaining: 6500
            property Connections lifecycle: Connections {
                target: entry.notification
                function onClosed(reason) { service.remove(entry); }
                function onSummaryChanged() { updated.restart(); }
                function onBodyChanged() { updated.restart(); }
                function onActionsChanged() { updated.restart(); }
                function onExpireTimeoutChanged() { updated.restart(); }
                function onUrgencyChanged() { updated.restart(); }
            }
            // A replacement updates several fields in one DBus transaction.
            property Timer updated: Timer { id: updated; interval: 0; onTriggered: service.present(entry) }
        }
    }
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        persistenceSupported: true
        imageSupported: true
        onNotification: n => {
            const existing = service.entries.find(e => e.notification === n);
            if (existing) { service.present(existing); return; }
            n.tracked = true;
            const entry = entryComponent.createObject(service, {notification: n});
            service.present(entry);
        }
    }
    Timer {
        interval: 100; repeat: true; running: service.popups.length > 0 && Hub.page === ""
        onTriggered: service.popups.forEach(entry => {
            if (entry.hovered || entry.remaining < 0) return;
            entry.remaining -= interval;
            if (entry.remaining <= 0) service.hidePopup(entry);
        })
    }
}
