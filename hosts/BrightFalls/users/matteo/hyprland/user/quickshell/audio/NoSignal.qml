pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Inputs that are attached and running but deliver no samples: the ALSA
// capture PCM is RUNNING and its hw_ptr does not move. Silence still moves
// it, so a quiet room is not flagged. Some USB microphones get stuck like
// this until their cable is replugged, and nothing else in PipeWire or ALSA
// shows it.
//
// /proc is read only while an input runs (a program or a level monitor
// records from it), and once when an input appears (shell start included),
// by opening it for about 1.5 s through a level monitor. Reads stop once two
// of them decide, so an input that hangs later in the same run is not seen
// until it starts running again. A flagged input is read on while it runs.
// A flag lasts until samples flow or the input goes away, and sends one
// desktop notification.
Singleton {
    id: root

    // Where card<N>/pcm<D>c/sub<S>/status is read. A directory holding a
    // copy of that tree fakes a device's state; cards missing from it are
    // never flagged.
    property string statusRoot: "/proc/asound"

    // Node ids of the inputs with no signal.
    readonly property var ids: Array.from(watches.instances).filter(w => w.verdict === "none").map(w => w.node.id)
    readonly property bool any: ids.length > 0

    readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource)

    function has(node: PwNode): bool {
        return node !== null && ids.includes(node.id);
    }

    function inputName(n: PwNode): string {
        return (n.description || n.nickname || n.name).replace(/ (Analog|Digital|Pro)( Stereo| Mono| Surround [0-9.]+)?$/, "");
    }

    // Serials notified about, leaving out inputs that are gone.
    function notifiedNow(): var {
        const present = sources.map(s => s.properties["object.serial"] ?? "");
        return persist.notified.split(",").filter(s => s !== "" && present.includes(s));
    }

    function forget(n: PwNode): void {
        const serial = n.properties["object.serial"] ?? "";
        persist.notified = notifiedNow().filter(s => s !== serial).join(",");
    }

    function notify(n: PwNode): void {
        const serial = n.properties["object.serial"] ?? "";
        const done = notifiedNow();
        if (done.includes(serial))
            return;
        persist.notified = done.concat([serial]).join(",");
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", "Audio", "0", "audio-input-microphone", `${inputName(n)} sends no signal`, "Unplug its cable for a few seconds and plug it back.", "[]", "{}", "int32 -1"]);
    }

    // Node properties, alsa.card among them, arrive once a node is bound.
    PwObjectTracker {
        objects: root.sources
    }

    PersistentProperties {
        id: persist

        reloadableId: "audio-nosignal"

        // object.serial of each flagged input already notified about,
        // comma-separated. A replugged device comes back with a new serial.
        property string notified: ""
    }

    Variants {
        id: watches

        model: root.sources.filter(n => (n.properties["alsa.card"] ?? "") !== "")

        Watch {}
    }

    component Watch: Scope {
        id: watch

        required property PwNode modelData
        readonly property PwNode node: modelData
        readonly property string statusPath: `${root.statusRoot}/card${node.properties["alsa.card"]}/pcm${node.properties["alsa.device"] ?? 0}c/sub${node.properties["alsa.subdevice"] ?? 0}/status`
        // Level monitors included: they run the device as much as a program.
        readonly property var links: Pipewire.linkGroups.values.filter(g => g.source === node)
        readonly property bool running: links.some(g => g.state === PwLinkState.Active)

        // "" until known, then "ok" or "none".
        property string verdict: ""
        property bool probing: false
        // hw_ptr at the previous read that found the PCM running, or "".
        property string last: ""
        property int reads: 0
        property bool decided: false

        function begin(): void {
            last = "";
            reads = 0;
            decided = false;
            sampler.restart();
        }

        function take(text: string): void {
            const state = text.match(/^state:\s*(\S+)/m)?.[1] ?? "";
            const ptr = text.match(/^hw_ptr\s*:\s*(\d+)/m)?.[1] ?? "";
            reads += 1;
            if (state === "RUNNING" && ptr !== "") {
                if (last !== "") {
                    verdict = ptr === last ? "none" : "ok";
                    decided = true;
                }
                last = ptr;
            } else {
                last = "";
            }
            if (decided || reads >= 6)
                probing = false;
            // A flagged input that something else runs is read on, so the
            // flag goes the moment samples flow.
            if ((decided && !(verdict === "none" && running)) || (!decided && reads >= 6))
                sampler.stop();
        }

        onVerdictChanged: {
            if (verdict === "none")
                root.notify(node);
            else if (verdict === "ok")
                root.forget(node);
        }
        onRunningChanged: {
            if (running)
                begin();
            else if (!probing)
                sampler.stop();
        }

        Component.onCompleted: {
            if (!running)
                probing = true;
            begin();
        }

        // Link state is only known for bound links.
        PwObjectTracker {
            objects: watch.links
        }

        // Opens the device for the check when nothing else has it open.
        PwNodePeakMonitor {
            node: watch.node
            enabled: watch.probing
        }

        // 750 ms between reads: a working device moves hw_ptr by tens of
        // thousands of frames in that time.
        Timer {
            id: sampler

            interval: 750
            repeat: true
            onTriggered: if (!read.running)
                read.running = true
        }

        Process {
            id: read

            command: ["cat", watch.statusPath]
            stdout: StdioCollector {
                onStreamFinished: watch.take(text)
            }
        }
    }
}
