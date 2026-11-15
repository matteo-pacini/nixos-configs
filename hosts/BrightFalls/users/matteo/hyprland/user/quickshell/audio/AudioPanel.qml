pragma Singleton

import QtQuick
import Quickshell

// What Bar.qml and Audio.qml share about the audio panel.
Singleton {
    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""

    // Asks Audio.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
}
