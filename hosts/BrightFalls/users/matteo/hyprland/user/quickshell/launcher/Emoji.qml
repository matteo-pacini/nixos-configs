pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// The launcher's emoji list and its search. emoji.txt beside this file has
// one "<emoji>\t<name>" line per emoji and is read in the background on the
// first load().
Singleton {
    id: root

    // [{ char, name }], in the data file's order; empty until it has loaded.
    property var entries: []
    readonly property int limit: 50

    function load() {
        data.path = Quickshell.shellPath("launcher/emoji.txt");
    }

    function search(query) {
        return (query.trim() === "" ? entries : Apps.rank(entries, query)).slice(0, limit);
    }

    FileView {
        id: data

        onLoaded: root.entries = text().split("\n").filter(line => line !== "").map(line => {
            const tab = line.indexOf("\t");
            return { char: line.slice(0, tab), name: line.slice(tab + 1) };
        })
        onLoadFailed: error => console.warn("emoji.txt:", FileViewError.toString(error))
    }
}
