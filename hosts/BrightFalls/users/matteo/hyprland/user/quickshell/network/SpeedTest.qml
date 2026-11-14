import QtQuick
import Quickshell
import Quickshell.Io

// One speed test run with cfspeedtest (speed.cloudflare.com), found on PATH.
// This file is the only place that knows the tool: its command, its output
// and how a result is read from it.
//
// fast-cli (fast.com) is not used: it prints rates of 1 Gb/s and over as
// whole Gb/s, and its JSON gives that whole number as Mb/s, so a 2.5 Gb/s
// link reads "2".
Scope {
    id: root

    // The `tool` field of a stored record.
    readonly property string tool: "cfspeedtest"
    readonly property bool running: process.running

    signal latency(real ms)
    // `direction` is "download" or "upload". `mbps` is the rate of the
    // request that just finished, so it moves with payload size.
    signal progress(string direction, real mbps)
    // The direction's result, as cfspeedtest's summary will give it: the
    // mean of the requests of the largest payload size it reached.
    signal directionDone(string direction, real mbps)
    signal finished(real download, real upload, real ping)
    signal failed(string reason)

    property string buffer: ""
    property real ping: -1
    property string direction: ""
    // Direction -> { payload, rates }: the requests of the payload size
    // being measured, the last one reached so far.
    property var samples: ({})
    property var summary: ({})
    property bool exited: false
    property bool cancelled: false

    function start(): void {
        buffer = "";
        ping = -1;
        direction = "";
        samples = {};
        summary = {};
        exited = false;
        cancelled = false;
        process.running = true;
    }

    // Stops the run; none of the signals above fire for it afterwards.
    function cancel(): void {
        cancelled = true;
        process.running = false;
    }

    function mean(rates: var): real {
        return rates.reduce((a, b) => a + b, 0) / rates.length;
    }

    function endDirection(): void {
        const s = samples[direction];
        if (s && s.rates.length > 0)
            directionDone(direction, mean(s.rates));
    }

    function parse(line: string): void {
        let m = line.match(/Avg GET request latency\s+([\d.]+)\s*ms/);
        if (m) {
            ping = Number(m[1]);
            latency(ping);
            return;
        }
        m = line.match(/^(Download|Upload)\s+(\S+)\s+\|\s+min\s+[\d.]+\s+max\s+[\d.]+\s+avg\s+([\d.]+)/);
        if (m) {
            // Rows come smallest payload first; the last one counts.
            summary[m[1].toLowerCase()] = Number(m[3]);
            return;
        }
        m = line.match(/^(Download|Upload)\s+(\S+)\s+\[[=\-]*\]\s+([\d.]+)\s*mbit\/s/);
        if (!m)
            return;
        const dir = m[1].toLowerCase();
        if (dir !== direction) {
            if (direction !== "")
                endDirection();
            direction = dir;
        }
        const rate = Number(m[3]);
        const s = samples[dir];
        if (!s || s.payload !== m[2])
            samples[dir] = {
                payload: m[2],
                rates: [rate]
            };
        else
            s.rates.push(rate);
        progress(dir, rate);
    }

    Process {
        id: process

        command: ["cfspeedtest"]
        stdout: SplitParser {
            // Progress lines end in carriage returns, so the stream is
            // split here on both.
            splitMarker: ""
            onRead: data => {
                if (root.cancelled)
                    return;
                const parts = (root.buffer + data).split(/[\r\n]/);
                root.buffer = parts.pop();
                for (const line of parts)
                    root.parse(line.trim());
            }
        }
        stderr: StdioCollector {
            id: errors
        }

        onExited: (code, status) => {
            root.exited = true;
            if (root.cancelled)
                return;
            if (root.buffer !== "")
                root.parse(root.buffer.trim());
            const down = root.summary.download, up = root.summary.upload;
            if (code === 0 && down !== undefined && up !== undefined && root.ping >= 0) {
                if (root.direction === "upload")
                    root.directionDone("upload", up);
                root.finished(down, up, root.ping);
                return;
            }
            const last = errors.text.trim().split("\n").pop();
            root.failed(code !== 0 ? `${root.tool} exited with ${code}${last ? ": " + last : ""}` : `${root.tool} gave no result`);
        }
        // A command that cannot start ends with no exited signal.
        onRunningChanged: if (!running && !root.exited && !root.cancelled)
            root.failed(`${root.tool} not found`)
    }
}
