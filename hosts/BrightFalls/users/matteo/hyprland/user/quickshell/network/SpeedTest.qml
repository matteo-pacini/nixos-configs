import QtQuick
import Quickshell
import Quickshell.Io

// One speed test run with one provider, its tool found on PATH. This file is
// the only place that knows the providers: their tools, command lines,
// output and how a result is read from it.
//
// fast-cli (fast.com) is not used: it prints rates of 1 Gb/s and over as
// whole Gb/s, and its JSON gives that whole number as Mb/s, so a 2.5 Gb/s
// link reads "2".
Scope {
    id: root

    // In the order the panel lists them; the first is the default. `id` is
    // the `provider` field of a stored record, `tool` its `tool` field.
    readonly property var providers: [
        {
            id: "cloudflare",
            name: "Cloudflare",
            host: "speed.cloudflare.com",
            tool: "cfspeedtest",
            command: ["cfspeedtest"],
            parse: line => root.parseCloudflare(line),
            result: () => root.resultCloudflare()
        },
        {
            id: "speedtest",
            name: "Speedtest.net",
            host: "speedtest.net · nearest server",
            tool: "speedtest",
            // The Ookla CLI refuses to run until both are accepted.
            command: ["speedtest", "--accept-license", "--accept-gdpr", "--format=jsonl", "--progress=yes", "--progress-update-interval=250"],
            parse: line => root.parseSpeedtest(line),
            result: () => root.run.result ?? null
        }
    ]
    // The provider of the current or last run.
    property var provider: providers[0]
    readonly property bool running: process.running

    signal latency(real ms)
    // `direction` is "download" or "upload"; `mbps` is the provider's live
    // figure for it.
    signal progress(string direction, real mbps)
    // The direction's result, as the provider's final figures will give it.
    signal directionDone(string direction, real mbps)
    signal finished(real download, real upload, real ping)
    signal failed(string reason)

    property string buffer: ""
    // The provider's parse state for this run.
    property var run: ({})
    property bool exited: false
    property bool cancelled: false

    function find(id: string): var {
        return providers.find(p => p.id === id) ?? null;
    }

    function start(id: string): void {
        provider = find(id) ?? providers[0];
        buffer = "";
        run = {};
        exited = false;
        cancelled = false;
        process.command = provider.command;
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

    // cfspeedtest, text mode. The live figure is the rate of the request
    // that just finished, so it moves with payload size. A direction's
    // result is the mean of the requests of the largest payload size it
    // reached, which is what its summary gives as `avg`.
    function endCloudflareDirection(): void {
        const s = run.samples?.[run.direction];
        if (s && s.rates.length > 0)
            directionDone(run.direction, mean(s.rates));
    }

    function parseCloudflare(line: string): void {
        run.samples = run.samples ?? {};
        run.summary = run.summary ?? {};
        let m = line.match(/Avg GET request latency\s+([\d.]+)\s*ms/);
        if (m) {
            run.ping = Number(m[1]);
            latency(run.ping);
            return;
        }
        m = line.match(/^(Download|Upload)\s+(\S+)\s+\|\s+min\s+[\d.]+\s+max\s+[\d.]+\s+avg\s+([\d.]+)/);
        if (m) {
            // Rows come smallest payload first; the last one counts.
            run.summary[m[1].toLowerCase()] = Number(m[3]);
            return;
        }
        m = line.match(/^(Download|Upload)\s+(\S+)\s+\[[=\-]*\]\s+([\d.]+)\s*mbit\/s/);
        if (!m)
            return;
        const dir = m[1].toLowerCase();
        if (dir !== run.direction) {
            if (run.direction)
                endCloudflareDirection();
            run.direction = dir;
        }
        const rate = Number(m[3]);
        const s = run.samples[dir];
        if (!s || s.payload !== m[2])
            run.samples[dir] = {
                payload: m[2],
                rates: [rate]
            };
        else
            s.rates.push(rate);
        progress(dir, rate);
    }

    function resultCloudflare(): var {
        const down = run.summary?.download, up = run.summary?.upload;
        if (down === undefined || up === undefined || !(run.ping >= 0))
            return null;
        if (run.direction === "upload")
            directionDone("upload", up);
        return {
            download: down,
            upload: up,
            ping: run.ping
        };
    }

    // Ookla CLI, one JSON object per line. Bandwidths are bytes per second
    // (its machine formats always use bytes); the live figure is its running
    // mean for the direction. The first upload line can carry INT64_MIN as
    // bandwidth, hence the > 0 test.
    function parseSpeedtest(line: string): void {
        let o;
        try {
            o = JSON.parse(line);
        } catch (e) {
            return;
        }
        const mbps = bytes => bytes * 8 / 1e6;
        if (o.type === "ping" && o.ping?.progress >= 1) {
            latency(o.ping.latency);
        } else if ((o.type === "download" || o.type === "upload") && o[o.type]?.bandwidth > 0) {
            const d = o[o.type];
            if (d.progress >= 1)
                directionDone(o.type, mbps(d.bandwidth));
            else
                progress(o.type, mbps(d.bandwidth));
        } else if (o.type === "result" && o.download?.bandwidth > 0 && o.upload?.bandwidth > 0) {
            run.result = {
                download: mbps(o.download.bandwidth),
                upload: mbps(o.upload.bandwidth),
                ping: o.ping?.latency ?? NaN
            };
        } else if (o.type === "log" && o.level === "error") {
            run.error = o.message;
        }
    }

    // The last stderr line, or the message of an Ookla JSON log line.
    function errorText(): string {
        if (run.error)
            return run.error;
        const last = errors.text.trim().split("\n").pop() ?? "";
        try {
            return JSON.parse(last).message ?? last;
        } catch (e) {
            return last;
        }
    }

    Process {
        id: process

        stdout: SplitParser {
            // cfspeedtest ends progress lines in carriage returns, so the
            // stream is split here on both.
            splitMarker: ""
            onRead: data => {
                if (root.cancelled)
                    return;
                const parts = (root.buffer + data).split(/[\r\n]/);
                root.buffer = parts.pop();
                for (const line of parts)
                    root.provider.parse(line.trim());
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
                root.provider.parse(root.buffer.trim());
            const r = code === 0 ? root.provider.result() : null;
            if (r && !isNaN(r.ping)) {
                root.finished(r.download, r.upload, r.ping);
                return;
            }
            const last = root.errorText();
            root.failed(code !== 0 ? `${root.provider.tool} exited with ${code}${last ? ": " + last : ""}` : `${root.provider.tool} gave no result`);
        }
        // A command that cannot start ends with no exited signal.
        onRunningChanged: if (!running && !root.exited && !root.cancelled)
            root.failed(`${root.provider.tool} not found`)
    }
}
