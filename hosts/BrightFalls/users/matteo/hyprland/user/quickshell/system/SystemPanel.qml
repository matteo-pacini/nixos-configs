pragma Singleton

import QtQuick
import Quickshell

// What Bar.qml and System.qml share about the system panel.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    // Name of the monitor whose bar item the pointer rests on, or "".
    property string hoverScreen: ""
    // Monitor name -> { icon, window }: the bar's system item on that monitor
    // and the PanelWindow it is in.
    property var icons: ({})

    // Asks System.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)

    function register(screen: string, icon: Item, window: PanelWindow): void {
        icons[screen] = {
            icon,
            window
        };
    }

    // Horizontal centre of the system item on `screen`, in that monitor's
    // coordinates, or -1 when no bar has registered one.
    function iconCentre(screen: string): real {
        const entry = icons[screen];
        if (!entry || !entry.icon || !entry.window)
            return -1;
        return entry.icon.mapToItem(null, entry.icon.width / 2, 0).x + entry.window.margins.left;
    }
}
