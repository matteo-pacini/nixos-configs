import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// A notification on screen: when it arrived, how long it has left, and a lock
// that keeps it readable through its leave animation after it closes.
QtObject {
    id: entry

    required property Notification notification
    readonly property string app: notification.appName
    // When it arrived or was last replaced, in ms since the epoch.
    property real time
    // Milliseconds until it expires; Notifications.qml counts it down while
    // its deck is not hovered. Infinity never expires.
    property real left
    // Set when the notification closes; the entry stays for the leave
    // animation, then sends finished().
    property bool closing: false
    // Height of its card fully shown, kept by the card.
    property real cardHeight: 0

    signal finished

    // Low 5 s, normal 8 s, critical never; a timeout from the sender wins
    // for the first two, up to 30 s, and 0 means never, as the spec says.
    function timeout() {
        if (notification.urgency === NotificationUrgency.Critical || notification.expireTimeout === 0)
            return Infinity;
        // In milliseconds, as sent over D-Bus, though Quickshell documents
        // seconds: Notification::updateProperties stores it unconverted.
        if (notification.expireTimeout > 0)
            return Math.min(notification.expireTimeout, 30000);
        return notification.urgency === NotificationUrgency.Low ? 5000 : 8000;
    }

    function refresh() {
        time = Date.now();
        left = timeout();
    }

    readonly property RetainableLock lock: RetainableLock {
        object: entry.notification
        locked: true
    }

    // A replacement (same id) updates the notification in place without a
    // new notification signal, and only changed properties notify. Each
    // notify-send run sends its own pid as a hint, so even a replacement with
    // the same text restarts the timeout.
    readonly property Connections watch: Connections {
        target: entry.notification

        function onClosed() {
            entry.closing = true;
        }
        function onSummaryChanged() {
            entry.refresh();
        }
        function onBodyChanged() {
            entry.refresh();
        }
        function onHintsChanged() {
            entry.refresh();
        }
    }

    readonly property Timer leave: Timer {
        interval: 200
        running: entry.closing
        onTriggered: entry.finished()
    }

    Component.onCompleted: refresh()
}
