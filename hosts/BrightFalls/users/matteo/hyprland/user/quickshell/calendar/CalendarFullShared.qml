pragma Singleton

import QtQuick
import Quickshell

// Where the calendar's big view (CalendarFull.qml) is open, and the requests
// other parts of the shell send it. Registered in Dropdowns, so it closes and
// is closed like a drop-down.
Singleton {
    // Name of the monitor the big view is open on, or "" while it is closed.
    property string screen: ""

    // Asks CalendarFull.qml to open the big view on `screen`, or close it.
    signal toggleRequested(string screen)
    // Asks CalendarFull.qml to open the big view on `screen`, if closed, with
    // `day` ("YYYY-MM-DD") selected.
    signal showRequested(string screen, string day)
}
