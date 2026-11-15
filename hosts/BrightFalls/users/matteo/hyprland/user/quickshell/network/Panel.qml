pragma Singleton

import QtQuick
import Quickshell

// What Bar.qml and Network.qml share about the network panel.
Singleton {
    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""

    // Asks Network.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
}
