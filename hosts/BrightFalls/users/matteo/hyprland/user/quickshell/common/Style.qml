pragma Singleton

import QtQuick
import Quickshell
import qs

// Measures and derived colours the shell's surfaces share. The palette and
// fonts themselves are Theme.qml's.
Singleton {
    // The bar's distance from the monitor's top and side edges, and its
    // height (Bar.qml).
    readonly property int barMargin: 6
    readonly property int barHeight: 34
    // The gap between the bar and anything that hangs under it.
    readonly property int belowBar: 8
    // Where a drop-down panel's card starts, from the monitor's top.
    readonly property int panelTop: barMargin + barHeight + belowBar
    // The closest a card comes to the monitor's side edges.
    readonly property int edge: 6
    // Corner radius of the bar, cards and modals.
    readonly property int radius: 10

    // The fill of the bar, cards and modals.
    readonly property color surface: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
    // Secondary text, between foreground and comment.
    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))
    // The empty part of bars and rings.
    readonly property color track: Qt.darker(Theme.background, 1.5)
    // The dimmed desktop behind a centred modal.
    readonly property color scrim: Qt.rgba(15 / 255, 16 / 255, 22 / 255, 0.5)
}
