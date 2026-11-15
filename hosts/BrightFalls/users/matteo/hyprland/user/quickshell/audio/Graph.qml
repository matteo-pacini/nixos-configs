import QtQuick
import Quickshell
import Quickshell.Io

// What PipeWire knows that Quickshell does not expose: each node's
// negotiated format, its driver and resampler quality, and each client's
// API. One pw-dump per refresh(); a refresh asked for while one runs is
// done once it ends.
Scope {
    id: root

    // Node id -> { format, rate, channels, driver, client, quality }. format
    // is PipeWire's name (S16LE, F32P...); rate and channels are 0 and
    // driver and client -1 when not known; quality is the node's own
    // resample.quality, or -1.
    property var nodes: ({})
    // Client id -> client.api, "" for a native PipeWire client.
    property var clients: ({})
    property bool known: false
    property bool again: false

    function refresh(): void {
        if (dump.running)
            again = true;
        else
            dump.running = true;
    }

    function parse(text: string): void {
        let objects;
        try {
            objects = JSON.parse(text);
        } catch (e) {
            console.warn("audio: pw-dump:", e.message);
            return;
        }
        const nodes = {}, clients = {};
        for (const o of objects) {
            const props = o.info?.props ?? {};
            if (o.type === "PipeWire:Interface:Client") {
                clients[o.id] = props["client.api"] ?? "";
            } else if (o.type === "PipeWire:Interface:Node") {
                const format = o.info?.params?.Format?.[0] ?? {};
                const pairs = o.info?.params?.Props?.find(p => Array.isArray(p.params))?.params ?? [];
                const at = pairs.indexOf("resample.quality");
                nodes[o.id] = {
                    format: format.format ?? "",
                    rate: format.rate ?? 0,
                    channels: format.channels ?? 0,
                    driver: props["node.driver-id"] ?? -1,
                    client: props["client.id"] ?? -1,
                    quality: at >= 0 ? pairs[at + 1] : -1
                };
            }
        }
        root.nodes = nodes;
        root.clients = clients;
        root.known = true;
    }

    Process {
        id: dump

        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: code => {
            if (code !== 0)
                console.warn("audio: pw-dump exited with", code);
            if (root.again) {
                root.again = false;
                running = true;
            }
        }
    }
}
