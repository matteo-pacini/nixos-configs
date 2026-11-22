import QtQuick
import qs

// The tune's waveform as columns of dots: `cols` holds each column's dot
// count (odd, centred on the middle row), the first `played` columns are
// lit purple and the rest current_line; `forming` draws them all cyan, for a
// tune that is being composed. 5 px pitch, 3 px dots.
Canvas {
    id: root

    property var cols: []
    property int played: 0
    property bool forming: false

    readonly property int pitch: 5
    readonly property int dot: 3
    readonly property int rows: 13
    readonly property color lit: forming ? Theme.cyan : Theme.purple
    readonly property color unlit: forming ? Theme.cyan : Theme.currentLine

    implicitWidth: cols.length * pitch
    implicitHeight: (rows - 1) * pitch + dot

    onColsChanged: requestPaint()
    onPlayedChanged: requestPaint()
    onLitChanged: requestPaint()
    onUnlitChanged: requestPaint()

    onPaint: {
        const g = getContext("2d");
        g.reset();
        for (let x = 0; x < cols.length; x++) {
            const n = cols[x];
            const top = (rows - n) / 2;
            g.fillStyle = x < played ? lit : unlit;
            for (let y = 0; y < n; y++)
                g.fillRect(x * pitch + 1, (top + y) * pitch, dot, dot);
        }
    }
}
