pragma Singleton

import QtQuick
import Quickshell

// What Bar.qml and System.qml share about the system panel.
Singleton {
    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    // Name of the monitor whose bar item the pointer rests on, or "".
    property string hoverScreen: ""

    // Asks System.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
}
