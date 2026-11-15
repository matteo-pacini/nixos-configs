pragma Singleton

import QtQuick
import Quickshell

// What Bar.qml and TrayMenu.qml share about the tray menu.
Singleton {
    // Name of the monitor the menu is open on, or "" while it is closed.
    property string screen: ""

    // Asks TrayMenu.qml to open a SystemTrayItem's menu on `screen`, under
    // the item Bar.qml anchored as "tray" there.
    signal openRequested(var item, string screen)
    // Asks TrayMenu.qml to close the menu; the toggle Dropdowns expects.
    signal toggleRequested(string screen)
}
