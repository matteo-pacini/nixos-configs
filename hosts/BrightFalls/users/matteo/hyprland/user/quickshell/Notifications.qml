import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.notifications

// The notification daemon (org.freedesktop.Notifications). Popups sit at the
// top right of the focused monitor, under the bar, one deck per app; critical
// ones (urgency 2) sit above them, one card each, and also above fullscreen
// windows. Over IPC:
//   qs ipc call notifications dismissNewest
//   qs ipc call notifications dismissAll
//   qs ipc call notifications toggleDnd
Scope {
    id: root

    // Every notification on screen, closing ones included until their leave
    // animation ends.
    property list<Entry> entries
    property real now: Date.now()
    // App name of the deck under the pointer, whose timeouts are paused, or
    // null. Not "": that is the name of an app that sends none.
    property var hoveredDeck: null

    // Critical ones get their own surface above fullscreen windows; the rest
    // are decked under the bar, hidden while a fullscreen window is up.
    readonly property var normal: entries.filter(e => e.notification.urgency !== NotificationUrgency.Critical)
    // Newest first. A closing card leaves at once: the surface it is on costs
    // a game direct scanout for as long as it exists.
    readonly property var critical: entries.filter(e => e.notification.urgency === NotificationUrgency.Critical && !e.closing).sort((a, b) => b.time - a.time)

    // App names, the deck with the newest notification first.
    readonly property var decks: {
        const newest = {};
        for (const e of normal)
            newest[e.app] = Math.max(newest[e.app] ?? 0, e.time);
        return Object.keys(newest).sort((a, b) => newest[b] - newest[a]);
    }

    readonly property int cardWidth: 380
    readonly property int peekHeight: 30
    readonly property int peekStep: 10
    readonly property int openGap: 6
    readonly property int animation: 200
    // Room around the cards for their shadows; the input mask leaves it out.
    readonly property int shadowPad: 40

    function live() {
        return entries.filter(e => !e.closing);
    }

    function dismissNewest() {
        const shown = live();
        if (shown.length > 0)
            shown.reduce((a, b) => b.time > a.time ? b : a).notification.dismiss();
    }

    function dismissAll() {
        for (const e of live())
            e.notification.dismiss();
    }

    // Survives Quickshell's reload on a file change, which would otherwise
    // turn do-not-disturb off unnoticed.
    PersistentProperties {
        id: persist

        reloadableId: "notifications"

        property bool dnd: false
    }

    Component {
        id: entryComponent

        Entry {}
    }

    NotificationServer {
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: n => {
            // Ones carried over from before a reload were already shown.
            if (persist.dnd && !n.lastGeneration && n.urgency !== NotificationUrgency.Critical) {
                // Not tracked, so the server drops it after this handler and
                // tells the sender it expired.
                n.expire();
                return;
            }
            n.tracked = true;
            if (root.entries.length === 0) {
                // Picked when the first popup appears and kept until the
                // last one goes, so popups do not jump between monitors.
                const name = Hyprland.focusedMonitor?.name;
                window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
                root.now = Date.now();
            }
            const entry = entryComponent.createObject(root, {
                notification: n
            });
            entry.finished.connect(() => {
                root.entries = root.entries.filter(e => e !== entry);
                entry.destroy();
            });
            root.entries = [...root.entries, entry];
        }
    }

    IpcHandler {
        target: "notifications"

        function dismissNewest(): void {
            root.dismissNewest();
        }
        function dismissAll(): void {
            root.dismissAll();
        }
        function toggleDnd(): void {
            persist.dnd = !persist.dnd;
            console.info("do not disturb:", persist.dnd ? "on" : "off");
        }
    }

    // Counts timeouts down, except in the hovered deck, and moves the
    // relative times on.
    Timer {
        interval: 250
        repeat: true
        running: root.entries.length > 0
        onTriggered: {
            const t = Date.now();
            const elapsed = t - root.now;
            root.now = t;
            for (const e of root.live()) {
                if (e.app === root.hoveredDeck)
                    continue;
                e.left -= elapsed;
                if (e.left <= 0)
                    e.notification.expire();
            }
        }
    }

    // Critical cards: Overlay, which Hyprland draws above fullscreen windows,
    // with no keyboard focus and input only on the cards. It exists only
    // while one is up, and appears and goes without a fade (layer rule in
    // hypr/rules.lua).
    PanelWindow {
        id: criticalWindow

        screen: window.screen
        visible: root.critical.length > 0
        color: "transparent"
        anchors {
            top: true
            right: true
        }
        margins.top: 44 - 16
        implicitWidth: root.shadowPad + root.cardWidth + 6
        implicitHeight: 16 + criticalColumn.height + root.shadowPad
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "desk-notifications-critical"
        mask: Region {
            item: criticalColumn
        }

        Column {
            id: criticalColumn

            x: root.shadowPad
            y: 16
            width: root.cardWidth
            spacing: 8

            Repeater {
                model: ScriptModel {
                    values: root.critical
                    comparisonMode: ObjectComparison.Identity
                }

                Item {
                    id: criticalSlot

                    required property Entry modelData

                    width: root.cardWidth
                    height: criticalCard.implicitHeight

                    RectangularShadow {
                        anchors.fill: criticalCard
                        radius: criticalCard.radius
                        offset.y: 12
                        blur: 34
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }

                    Card {
                        id: criticalCard

                        width: parent.width
                        height: implicitHeight
                        entry: criticalSlot.modelData
                        now: root.now
                    }

                    Binding {
                        target: criticalSlot.modelData
                        property: "cardHeight"
                        value: criticalCard.implicitHeight
                    }
                }
            }
        }
    }

    PanelWindow {
        id: window

        visible: root.normal.length > 0
        color: "transparent"
        anchors {
            top: true
            right: true
        }
        // The cards start 44 px down, under the bar, and under any critical
        // cards; the window starts higher so the top card's shadow is not
        // cut off.
        margins.top: 44 - 16 + (criticalWindow.visible ? criticalColumn.height + 8 : 0)
        implicitWidth: root.shadowPad + root.cardWidth + 6
        implicitHeight: 16 + column.height + root.shadowPad
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "desk-notifications"
        mask: Region {
            item: column
        }

        Column {
            id: column

            x: root.shadowPad
            y: 16
            width: root.cardWidth
            spacing: 8

            move: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: root.animation
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.decks
                }

                // One app's notifications: the newest in front with up to two
                // strips peeking out below it, or, while hovered, all of them
                // in a list.
                Item {
                    id: deck

                    required property string modelData
                    readonly property var cards: root.normal.filter(e => e.app === modelData).sort((a, b) => b.time - a.time)
                    readonly property bool open: hover.hovered && cards.length > 1
                    readonly property real frontHeight: cards.length > 0 ? cards[0].cardHeight : 0

                    function cardY(i) {
                        let y = 0;
                        for (let k = 0; k < i; k++)
                            y += cards[k].cardHeight + root.openGap;
                        return y;
                    }

                    // For a deck that goes while hovered.
                    Component.onDestruction: {
                        if (root.hoveredDeck === modelData)
                            root.hoveredDeck = null;
                    }

                    width: root.cardWidth
                    height: {
                        const n = cards.length;
                        if (n === 0)
                            return 0;
                        return open ? cardY(n - 1) + cards[n - 1].cardHeight : frontHeight + root.peekStep * Math.min(n - 1, 2);
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: root.animation
                            easing.type: Easing.OutCubic
                        }
                    }

                    HoverHandler {
                        id: hover

                        onHoveredChanged: {
                            if (hovered)
                                root.hoveredDeck = deck.modelData;
                            else if (root.hoveredDeck === deck.modelData)
                                root.hoveredDeck = null;
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: deck.cards
                            comparisonMode: ObjectComparison.Identity
                        }

                        Item {
                            id: slot

                            required property Entry modelData
                            required property int index
                            readonly property bool peek: !deck.open && index > 0

                            property real enter: 0
                            property real leave: modelData.closing ? 1 : 0
                            property real depth: peek ? [1, 0.85, 0.55][index] ?? 0 : 1

                            NumberAnimation on enter {
                                from: 0
                                to: 1
                                duration: root.animation
                                easing.type: Easing.OutCubic
                            }
                            Behavior on leave {
                                NumberAnimation {
                                    duration: root.animation
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on depth {
                                NumberAnimation {
                                    duration: root.animation
                                }
                            }
                            Behavior on y {
                                NumberAnimation {
                                    duration: root.animation
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on height {
                                NumberAnimation {
                                    duration: root.animation
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: root.animation
                                }
                            }

                            readonly property real shown: enter * (1 - leave)

                            width: deck.width
                            height: peek ? root.peekHeight : modelData.cardHeight
                            x: 24 * (1 - shown)
                            y: deck.open ? deck.cardY(index) : index === 0 ? 0 : deck.frontHeight + root.peekStep * Math.min(index, 2) - root.peekHeight
                            z: -index
                            scale: peek ? (index === 1 ? 0.965 : 0.93) : 1
                            opacity: depth * shown

                            RectangularShadow {
                                anchors.fill: card
                                visible: !slot.peek
                                radius: card.radius
                                offset.y: 12
                                blur: 34
                                color: Qt.rgba(0, 0, 0, 0.5)
                            }

                            Card {
                                id: card

                                width: parent.width
                                height: parent.height
                                entry: slot.modelData
                                now: root.now
                                oneLine: slot.index === 0 && !deck.open && deck.cards.length > 1
                                more: slot.index === 0 && !deck.open ? deck.cards.length - 1 : 0
                                contentShown: !slot.peek
                            }

                            Binding {
                                target: slot.modelData
                                property: "cardHeight"
                                value: card.implicitHeight
                            }
                        }
                    }
                }
            }
        }
    }
}
