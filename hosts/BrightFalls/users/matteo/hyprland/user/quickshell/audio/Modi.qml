import QtQuick
import Quickshell
import Quickshell.Io

// The Modi's ALSA card as the kernel reports it: what its USB interface
// can take (stream0) and the format it is open with (pcm0p/sub0/hw_params,
// "closed" while PipeWire has it suspended). Read once per refresh().
Scope {
    id: root

    // ALSA card number, -1 when the Modi is not there.
    property int card: -1

    property var bits: []
    property var rates: []
    // USB asynchronous mode: the converter clocks itself.
    property bool clockOwn: false
    property int channels: 0

    property bool open: false
    property int openBits: 0
    property int openRate: 0

    function refresh(): void {
        if (card < 0) {
            open = false;
            return;
        }
        read.command = ["sh", "-c", 'cat "$1/stream0"; echo @hw; cat "$1/pcm0p/sub0/hw_params"', "sh", "/proc/asound/card" + card];
        read.running = true;
    }

    function formatBits(format: string): int {
        const m = format.match(/^[SU](\d+)/);
        return m ? Number(m[1]) : 0;
    }

    Process {
        id: read

        stdout: StdioCollector {
            onStreamFinished: {
                const [stream, hw] = text.split("\n@hw\n");
                const bits = new Set(), rates = new Set();
                let clockOwn = false, channels = 0;
                for (const line of stream.split("\n")) {
                    const t = line.trim();
                    let m;
                    if ((m = t.match(/^Bits: (\d+)$/)))
                        bits.add(Number(m[1]));
                    else if ((m = t.match(/^Rates: (.+)$/)))
                        m[1].split(",").forEach(r => rates.add(Number(r.trim())));
                    else if ((m = t.match(/^Channels: (\d+)$/)))
                        channels = Math.max(channels, Number(m[1]));
                    else if (/^Endpoint: .*\bOUT\b.*\(ASYNC\)/.test(t))
                        clockOwn = true;
                }
                root.bits = Array.from(bits).sort((a, b) => a - b);
                root.rates = Array.from(rates).filter(r => r > 0).sort((a, b) => a - b);
                root.clockOwn = clockOwn;
                root.channels = channels;

                const params = (hw ?? "").trim();
                const format = params.match(/^format: (\S+)$/m);
                const rate = params.match(/^rate: (\d+)/m);
                root.open = params !== "" && params !== "closed" && rate !== null;
                root.openBits = format ? root.formatBits(format[1]) : 0;
                root.openRate = rate ? Number(rate[1]) : 0;
            }
        }
    }
}
