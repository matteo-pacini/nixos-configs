import QtQuick
import qs

// The tune's waveform as columns of dots: `cols` holds each column's dot
// count (odd, centred on the middle row, at most `rows`), the first `played`
// columns are lit purple and the rest current_line. 5 px pitch, 3 px dots.
Canvas {
    id: root

    property var cols: []
    property int played: 0

    readonly property int pitch: 5
    readonly property int dot: 3
    readonly property int rows: 9

    implicitWidth: cols.length * pitch
    implicitHeight: (rows - 1) * pitch + dot

    onColsChanged: requestPaint()
    onPlayedChanged: requestPaint()

    onPaint: {
        const g = getContext("2d");
        g.reset();
        for (let x = 0; x < cols.length; x++) {
            const n = cols[x];
            const top = (rows - n) / 2;
            g.fillStyle = x < played ? Theme.purple : Theme.currentLine;
            for (let y = 0; y < n; y++)
                g.fillRect(x * pitch + 1, (top + y) * pitch, dot, dot);
        }
    }
}
