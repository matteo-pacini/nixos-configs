pragma Singleton

import QtQuick
import Quickshell

// The drop-down panels that hang under a bar item, so that one opening
// closes the others without any panel knowing the rest.
//
// A panel adds itself once with add(): its name and the singleton it shares
// with Bar.qml, which must have a `screen` property ("" while the panel is
// closed) and a `toggleRequested(string screen)` signal. Bar.qml adds, per
// monitor, the item each panel hangs under with anchor().
Singleton {
    id: root

    // Panel name -> its singleton shared with the bar.
    property var panels: ({})
    // "<panel>/<monitor>" -> { item, window }.
    property var anchors: ({})

    function add(name: string, shared: var): void {
        panels[name] = shared;
    }

    // Asks every open panel other than `name` to close.
    function closeOthers(name: string): void {
        for (const other of Object.keys(panels)) {
            const shared = panels[other];
            if (other !== name && shared.screen !== "")
                shared.toggleRequested(shared.screen);
        }
    }

    function anchor(name: string, screen: string, item: Item, window: PanelWindow): void {
        anchors[name + "/" + screen] = {
            item,
            window
        };
    }

    // Horizontal centre of panel `name`'s bar item on `screen`, in that
    // monitor's coordinates, or -1 when no bar has anchored one.
    function centre(name: string, screen: string): real {
        const entry = anchors[name + "/" + screen];
        if (!entry || !entry.item || !entry.window)
            return -1;
        return entry.item.mapToItem(null, entry.item.width / 2, 0).x + entry.window.margins.left;
    }
}
