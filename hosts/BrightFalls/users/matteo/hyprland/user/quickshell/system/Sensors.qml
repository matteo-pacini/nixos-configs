pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "decode.js" as D

// Every figure the bar's system item, its hover list and the system panel
// show, read straight from sysfs and procfs with FileViews. How much is read
// follows `level`:
//   0  panel closed, no hover: the CPU's and the eGPU's temperature, every 5 s
//   1  hover list: every temperature, each second (memory modules and NVMe
//      every 10 s)
//   2  panel open: everything, each second; slow and static facts every 10 s
//      or once on open
// Read-only: no file is opened for writing, LACT's socket is never used, and
// no *_alarm file is read (spd5118 clears its alarm when it is read).
Singleton {
    id: root

    readonly property int level: SystemPanel.screen !== "" ? 2 : SystemPanel.hoverScreen !== "" ? 1 : 0

    readonly property string lockedPath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/system/locked.json"

    // Where everything is, from discovery: hwmon directories resolved by
    // name and device, the GPUs and their PCI path, connectors, the NVMe
    // block device. Null until discovery has run.
    property var topo: null
    // False while the eGPU is runtime-suspended (or its reads fail): amdgpu
    // then refuses power and sensor reads, and FileView logs every refused
    // read, so those files are not read at all.
    property bool egpuAwake: true

    // The published figures, rebuilt after each read; see snapshot().
    property var s: ({})

    // Latest text or bytes of each source, by key. Not a binding source:
    // snapshot() reads it once per refresh.
    property var raw: ({})
    property var prev: ({})
    property real tickAt: 0

    readonly property string discoverScript: [
        "for h in /sys/class/hwmon/hwmon*; do printf 'hwmon %s %s %s\\n' \"$h\" \"$(cat \"$h/name\")\" \"$(readlink -f \"$h/device\")\"; done",
        // Byte 2 of gpu_metrics is its format: 2 is the APU layout.
        "for g in /sys/bus/pci/drivers/amdgpu/*:*; do printf 'gpu %s %s\\n' \"$(readlink -f \"$g\")\" \"$(od -An -tu1 -j2 -N1 \"$g/gpu_metrics\" 2>/dev/null | tr -d ' ')\"; done",
        "for c in /sys/class/drm/card*-*; do printf 'conn %s\\n' \"$(readlink -f \"$c\")\"; done",
        "for b in /sys/block/nvme*; do printf 'block %s\\n' \"$(readlink -f \"$b\")\"; done",
        "for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do printf 'freq %s\\n' \"$f\"; done"
    ].join("\n")

    function parseTopo(text: string): var {
        const hw = [];
        const gpus = [];
        const conns = [];
        const blocks = [];
        const freqs = [];
        for (const line of text.split("\n")) {
            const f = line.split(" ");
            if (f[0] === "hwmon" && f.length >= 4)
                hw.push({
                    dir: f[1],
                    name: f[2],
                    dev: f[3]
                });
            else if (f[0] === "gpu" && f[1])
                gpus.push({
                    path: f[1],
                    format: f[2] ?? ""
                });
            else if (f[0] === "conn" && f[1] && !/Writeback/.test(f[1]))
                conns.push(f[1]);
            else if (f[0] === "block" && f[1])
                blocks.push(f[1]);
            else if (f[0] === "freq" && f[1] && !f[1].includes("*"))
                freqs.push(f[1]);
        }
        freqs.sort((a, b) => Number(a.match(/cpu(\d+)/)[1]) - Number(b.match(/cpu(\d+)/)[1]));
        const named = name => hw.filter(h => h.name === name).sort((a, b) => a.dev.localeCompare(b.dev));
        const gpu = g => {
            if (!g)
                return null;
            const m = g.path.match(/^(\/sys\/devices\/pci[0-9a-f:]+)\/(.+)$/);
            const chain = m ? m[2].split("/") : [];
            const hop = chain.length >= 2 ? {
                port: m[1] + "/" + chain[0],
                device: m[1] + "/" + chain[0] + "/" + chain[1]
            } : null;
            return {
                path: g.path,
                address: g.path.split("/").pop(),
                hwmon: hw.find(h => h.name === "amdgpu" && h.dev === g.path)?.dir ?? "",
                hop,
                connectors: conns.filter(c => c.startsWith(g.path + "/drm/")).map(c => ({
                            dir: c,
                            name: c.split("/").pop().replace(/^card\d+-/, "")
                        })).sort((a, b) => a.name.localeCompare(b.name, undefined, {
                            numeric: true
                        }))
            };
        };
        const nvme = named("nvme")[0] ?? null;
        return {
            k10: named("k10temp")[0]?.dir ?? "",
            dimms: named("spd5118").map(h => h.dir),
            nvme: nvme?.dir ?? "",
            block: nvme ? blocks.find(b => b.startsWith(nvme.dev + "/")) ?? "" : "",
            igpu: gpu(gpus.find(g => g.format === "2")),
            egpu: gpu(gpus.find(g => g.format !== "2")),
            freqs
        };
    }

    // The files to read: { key, file, min (lowest level), max, rate, bin,
    // egpu (only while it is awake) }. rate: "fast" every second (every 5 s
    // at level 0), "slow" every 10 s, "once" when the panel opens.
    readonly property var sources: {
        const t = topo;
        if (!t)
            return [];
        const out = [];
        const add = (key, file, min, rate, extra) => {
            if (file)
                out.push(Object.assign({
                    key,
                    file,
                    min,
                    max: 2,
                    rate,
                    bin: false,
                    egpu: false
                }, extra ?? {}));
        };
        const k = t.k10;
        const e = t.egpu;
        const i = t.igpu;
        add("cpuTemp", k && k + "/temp1_input", 0, "fast");
        if (e) {
            // Junction, the temperature the card limits itself by.
            add("egpuJuncHw", e.hwmon && e.hwmon + "/temp2_input", 0, "fast", {
                max: 0,
                egpu: true
            });
            add("egpuStatus", e.path + "/power/runtime_status", 0, "fast", {
                max: 2
            });
            for (const n of [1, 2, 3])
                add("egpuCrit" + n, e.hwmon && `${e.hwmon}/temp${n}_crit`, 0, "once", {
                    egpu: true
                });
            add("egpuMetrics", e.path + "/gpu_metrics", 1, "fast", {
                bin: true,
                egpu: true
            });
            add("egpuVram", e.path + "/mem_info_vram_used", 2, "fast", {
                egpu: true
            });
            add("egpuVramTotal", e.path + "/mem_info_vram_total", 2, "once");
            add("egpuPwm", e.hwmon && e.hwmon + "/pwm1", 2, "fast", {
                egpu: true
            });
            add("egpuPwmEnable", e.hwmon && e.hwmon + "/pwm1_enable", 2, "once", {
                egpu: true
            });
            add("egpuCap", e.hwmon && e.hwmon + "/power1_cap", 2, "once", {
                egpu: true
            });
            add("egpuDevice", e.path + "/device", 2, "once");
            add("egpuRevision", e.path + "/revision", 2, "once");
            add("egpuDpmPcie", e.path + "/pp_dpm_pcie", 2, "slow", {
                egpu: true
            });
            if (e.hop) {
                add("linkSpeed", e.hop.device + "/current_link_speed", 2, "slow");
                add("linkWidth", e.hop.device + "/current_link_width", 2, "slow");
                add("linkMaxSpeed", e.hop.port + "/max_link_speed", 2, "once");
                add("linkMaxWidth", e.hop.port + "/max_link_width", 2, "once");
                for (const a of ["correctable", "nonfatal", "fatal"])
                    add("aerHop_" + a, `${e.hop.device}/aer_dev_${a}`, 2, "once");
            }
            for (const a of ["correctable", "nonfatal", "fatal"])
                add("aerGpu_" + a, `${e.path}/aer_dev_${a}`, 2, "once");
            e.connectors.forEach((c, n) => {
                add("econn" + n, c.dir + "/status", 2, "slow");
                add("econnOn" + n, c.dir + "/enabled", 2, "slow");
            });
        }
        if (i) {
            add("igpuMetrics", i.path + "/gpu_metrics", 1, "fast", {
                bin: true
            });
            add("igpuBusy", i.path + "/gpu_busy_percent", 2, "fast");
            add("igpuVram", i.path + "/mem_info_vram_used", 2, "fast");
            add("igpuVramTotal", i.path + "/mem_info_vram_total", 2, "once");
            add("igpuPower", i.hwmon && i.hwmon + "/power1_average", 2, "fast");
            add("igpuFreq", i.hwmon && i.hwmon + "/freq1_input", 2, "fast");
            add("igpuVolt", i.hwmon && i.hwmon + "/in0_input", 2, "fast");
            add("igpuVoltNb", i.hwmon && i.hwmon + "/in1_input", 2, "fast");
            i.connectors.forEach((c, n) => {
                add("iconn" + n, c.dir + "/status", 2, "slow");
                add("iconnOn" + n, c.dir + "/enabled", 2, "slow");
            });
        }
        t.dimms.forEach((d, n) => {
            add("dimm" + n, d + "/temp1_input", 1, "slow");
            add("dimmMax" + n, d + "/temp1_max", 1, "once");
            add("dimmCrit" + n, d + "/temp1_crit", 1, "once");
        });
        if (t.nvme) {
            add("nvmeTemp", t.nvme + "/temp1_input", 1, "slow");
            add("nvmeMax", t.nvme + "/temp1_max", 1, "once");
        }
        if (t.block) {
            add("block", t.block + "/stat", 2, "fast");
            add("blockSize", t.block + "/size", 2, "once");
        }
        t.freqs.forEach((f, n) => add("freq" + n, f, 2, "fast"));
        const cpu0 = "/sys/devices/system/cpu/cpu0/cpufreq/";
        add("cpuinfoMax", cpu0 + "cpuinfo_max_freq", 2, "once");
        add("scalingMax", cpu0 + "scaling_max_freq", 2, "once");
        add("governor", cpu0 + "scaling_governor", 2, "once");
        add("epp", cpu0 + "energy_performance_preference", 2, "once");
        add("cpuinfo", "/proc/cpuinfo", 2, "once");
        add("procStat", "/proc/stat", 2, "fast");
        add("meminfo", "/proc/meminfo", 2, "fast");
        add("loadavg", "/proc/loadavg", 2, "fast");
        add("netdev", "/proc/net/dev", 2, "fast");
        add("route", "/proc/net/route", 2, "once");
        add("locked", root.lockedPath, 2, "once");
        add("lact", "/etc/lact/config.yaml", 2, "once");
        return out;
    }

    // 0 normal, 1 warm (orange), 2 hot (red) for temperature `t` of `kind`.
    // From the kernel's own limits where it reports them (crit for the eGPU,
    // max and crit for the memory modules, max for the NVMe); the CPU and
    // iGPU report none, so theirs are fixed.
    function heat(kind: string, t: var): int {
        const x = s;
        switch (kind) {
        case "cpu":
            return D.heat(t, 75, 92);
        case "core":
            return D.heat(t, 85, 95);
        case "edge":
            return D.heat(t, x.edgeCrit - 20, x.edgeCrit - 10);
        case "junction":
            return D.heat(t, x.junctionCrit - 20, x.junctionCrit - 10);
        case "mem":
            return D.heat(t, x.memCrit - 20, x.memCrit - 10);
        case "igpu":
            return D.heat(t, 80, 95);
        case "dimm":
            return D.heat(t, x.dimmWarm, x.dimmHot);
        case "nvme":
            return D.heat(t, x.nvmeWarm, x.nvmeHot);
        }
        return 0;
    }

    function active(src: var): bool {
        if (level < src.min || level > src.max)
            return false;
        if (src.egpu && !egpuAwake)
            return false;
        // While closed the eGPU's state is read only when its temperature
        // read has failed, to learn when it wakes; that keeps the closed
        // state at two reads.
        if (src.key === "egpuStatus" && level === 0)
            return !egpuAwake;
        return true;
    }

    function tick(rate: string): void {
        const now = Date.now();
        for (let n = 0; n < views.count; n++) {
            const view = views.objectAt(n);
            // "once" sources are read when their path is set, on opening.
            // Slow ones are read by any tick that finds them due, so a
            // timer firing a moment early does not skip a read.
            if (view && view.on && (rate === "all" ? view.src.rate !== "once" : view.src.rate === rate || view.src.rate === "slow") && D.due(view.readAt, now, view.src.rate)) {
                view.readAt = now;
                view.reload();
            }
        }
        if (rate === "fast" || rate === "all")
            tickAt = Date.now();
        if ((rate === "slow" || rate === "all") && level === 2)
            df.running = true;
        commit.restart();
    }

    function num(key: string): var {
        const x = raw[key];
        if (x === null || x === undefined || typeof x !== "string")
            return null;
        const n = Number(x.trim());
        return x.trim() === "" || isNaN(n) ? null : n;
    }

    function milli(key: string): var {
        const n = num(key);
        return n === null ? null : n / 1000;
    }

    function str(key: string): string {
        const x = raw[key];
        return typeof x === "string" ? x.trim() : "";
    }

    function bytes(key: string): var {
        const x = raw[key];
        return x && typeof x === "object" && x.byteLength !== undefined ? x : null;
    }

    function snapshot(): void {
        const t = topo ?? {};
        const out = {};
        const at = tickAt;
        const p = prev;

        // Locked (Nix-set) rows.
        let locked = [];
        try {
            const parsed = JSON.parse(str("locked") || "null");
            locked = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            locked = [];
        }
        out.lockedPresent = str("locked") !== "";

        // CPU.
        const im = D.metrics(bytes("igpuMetrics"));
        out.cpuTemp = milli("cpuTemp");
        out.cpuHottest = im && im.coreTemps.length ? Math.max(...im.coreTemps) : null;
        const model = (str("cpuinfo").match(/^model name\s*:\s*(.+)$/m)?.[1] ?? "").replace(/^AMD\s+/, "").replace(/\s+w\/.*$/, "");
        out.cpuModel = model;
        const stat = raw.procStat ? D.cpuTimes(raw.procStat) : null;
        out.threadCount = stat ? stat.threads.length : (t.freqs?.length ?? 0);
        if (stat && p.stat && at > p.statAt) {
            out.cpuLoad = D.busyPercent(p.stat.total, stat.total);
            out.threads = stat.threads.map((c, n) => D.busyPercent(p.stat.threads[n], c) ?? 0);
        } else {
            out.cpuLoad = null;
            out.threads = [];
        }
        if (stat && at > (p.statAt ?? 0)) {
            p.stat = stat;
            p.statAt = at;
        }
        const freqs = (t.freqs ?? []).map((f, n) => num("freq" + n)).filter(x => x !== null);
        out.clockAvg = freqs.length ? freqs.reduce((a, b) => a + b, 0) / freqs.length : null;
        out.scalingMax = num("scalingMax");
        out.cpuinfoMax = num("cpuinfoMax");
        const cap = locked.find(r => r && r.id === "cpu-max");
        out.capNix = !!cap && out.scalingMax !== null && cap.khz === out.scalingMax;
        out.capFile = out.capNix ? String(cap.file ?? "") : "";
        out.packageW = num("igpuPower") === null ? null : num("igpuPower") / 1e6;
        out.governor = str("governor");
        out.epp = str("epp");
        out.loadavg = str("loadavg").split(/\s+/).slice(0, 3).join(" · ");

        // Memory.
        if (raw.meminfo) {
            const mi = D.meminfo(raw.meminfo);
            out.memTotal = mi.MemTotal ?? null;
            out.memUsed = mi.MemTotal !== undefined && mi.MemAvailable !== undefined ? mi.MemTotal - mi.MemAvailable : null;
            out.memCached = mi.Cached ?? null;
            out.memAvailable = mi.MemAvailable ?? null;
            out.memBuffers = mi.Buffers ?? null;
            out.memShared = mi.Shmem ?? null;
            out.swapTotal = mi.SwapTotal ?? 0;
            out.swapUsed = (mi.SwapTotal ?? 0) - (mi.SwapFree ?? 0);
        }
        out.dimms = (t.dimms ?? []).map((d, n) => milli("dimm" + n)).filter(x => x !== null);
        out.dimmWarm = milli("dimmMax0") ?? 55;
        out.dimmHot = milli("dimmCrit0") !== null ? milli("dimmCrit0") - 10 : 75;

        // eGPU.
        const e = t.egpu ?? null;
        out.egpuPresent = e !== null;
        out.egpuAwake = egpuAwake;
        const em = egpuAwake ? D.metrics(bytes("egpuMetrics")) : null;
        out.egpuEdge = em?.edge ?? null;
        out.egpuJunction = level === 0 ? milli("egpuJuncHw") : em?.junction ?? null;
        out.egpuMem = em?.mem ?? null;
        out.egpuVr = em ? [em.vrGfx, em.vrSoc, em.vrMem] : [];
        const crit = n => milli("egpuCrit" + n);
        out.edgeCrit = crit(1) ?? 100;
        out.junctionCrit = crit(2) ?? 110;
        out.memCrit = crit(3) ?? 100;
        out.egpuLoad = em?.gfxActivity ?? null;
        out.egpuVramUsed = num("egpuVram");
        out.egpuVramTotal = num("egpuVramTotal");
        out.fanRpm = em?.fanRpm ?? null;
        out.fanPct = num("egpuPwm") === null ? null : num("egpuPwm") / 255 * 100;
        out.egpuPower = em?.socketPower ?? null;
        out.egpuCap = num("egpuCap") === null ? null : num("egpuCap") / 1e6;
        out.coreClock = em?.gfxClock ?? null;
        out.memClock = em?.uClock ?? null;
        out.voltGfx = em?.voltGfx ?? null;
        out.voltSoc = em?.voltSoc ?? null;
        out.voltMem = em?.voltMem ?? null;
        out.throttle = em?.throttle ?? [];
        out.egpuDriving = e ? e.connectors.filter((c, n) => str("econn" + n) === "connected" && str("econnOn" + n) === "enabled").map(c => c.name) : [];
        out.igpuDriving = t.igpu ? t.igpu.connectors.filter((c, n) => str("iconn" + n) === "connected" && str("iconnOn" + n) === "enabled").map(c => c.name) : [];
        const device = str("egpuDevice");
        out.egpuName = device === "0x73bf" && str("egpuRevision") === "0xc1" ? "Radeon RX 6800 XT" : device ? `AMD GPU ${device.replace(/^0x/, "")}` : "";
        const cur = {
            speed: D.gts(str("linkSpeed")),
            width: num("linkWidth")
        };
        const max = {
            speed: D.gts(str("linkMaxSpeed")),
            width: num("linkMaxWidth")
        };
        out.link = {
            gen: D.pcieGen(cur.speed),
            width: cur.width,
            maxGen: D.pcieGen(max.speed),
            maxWidth: max.width,
            state: D.linkState(cur, max, D.linkPowerSaving(str("egpuDpmPcie")))
        };
        out.linkErrors = ["aerHop_", "aerGpu_"].reduce((sum, pre) => sum + ["correctable", "nonfatal", "fatal"].reduce((s, a) => s + D.aerTotal(str(pre + a)), 0), 0);
        const lact = e ? D.lactFan(str("lact"), e.address) : "";
        const pwmEnable = num("egpuPwmEnable");
        out.fanControl = lact !== "" ? lact : pwmEnable === 2 ? "firmware automatic" : pwmEnable === 1 ? "manual, set by another program" : pwmEnable === 0 ? "full speed" : "";
        const lactRow = locked.find(r => r && r.id === "lact");
        out.lactFile = lact !== "" && lactRow ? String(lactRow.file ?? "") : "";

        // iGPU.
        out.igpuPresent = !!t.igpu;
        // The APU's model name names its graphics: "... w/ Radeon 780M Graphics".
        out.igpuName = str("cpuinfo").match(/^model name\s*:.*w\/\s*(.+?)(?:\s+Graphics)?$/m)?.[1] ?? "";
        out.igpuTemp = im?.gfxTemp ?? null;
        out.igpuLoad = num("igpuBusy");
        out.igpuVramUsed = num("igpuVram");
        out.igpuVramTotal = num("igpuVramTotal");
        out.igpuClock = num("igpuFreq") === null ? null : num("igpuFreq") / 1e6;
        out.igpuVolt = num("igpuVolt") === null ? null : num("igpuVolt") / 1000;
        out.igpuVoltNb = num("igpuVoltNb") === null ? null : num("igpuVoltNb") / 1000;

        // Storage and network.
        out.nvmeTemp = milli("nvmeTemp");
        out.nvmeHot = milli("nvmeMax") ?? 80;
        out.nvmeWarm = out.nvmeHot - 10;
        out.nvmeSize = num("blockSize") === null ? null : num("blockSize") * 512;
        const block = raw.block ? D.blockStat(raw.block) : null;
        if (block && p.block && at > p.blockAt) {
            const dt = (at - p.blockAt) / 1000;
            out.readBps = (block[0] - p.block[0]) / dt;
            out.writeBps = (block[1] - p.block[1]) / dt;
            out.diskBusy = Math.min(100, (block[2] - p.block[2]) / (dt * 10));
        }
        if (block && at > (p.blockAt ?? 0)) {
            p.block = block;
            p.blockAt = at;
        }
        out.volumes = raw.df ? D.volumes(raw.df) : [];
        out.uplink = D.uplink(str("route"));
        const net = raw.netdev && out.uplink ? D.netBytes(raw.netdev, out.uplink) : null;
        if (net && p.net && at > p.netAt) {
            const dt = (at - p.netAt) / 1000;
            out.rxBps = (net[0] - p.net[0]) / dt;
            out.txBps = (net[1] - p.net[1]) / dt;
        }
        if (net && at > (p.netAt ?? 0)) {
            p.net = net;
            p.netAt = at;
        }
        s = out;
    }

    onLevelChanged: {
        // Figures left from the last time the panel was open would otherwise
        // show for a second, and the rates would span the time it was shut.
        if (level === 2) {
            prev = {};
            // A slow figure that is not due yet is kept: it is not read now.
            for (let n = 0; n < views.count; n++) {
                const view = views.objectAt(n);
                if (view && view.src.min === 2 && D.due(view.readAt, Date.now(), view.src.rate))
                    delete raw[view.src.key];
            }
            delete raw.df;
            discovery.running = true;
        }
        // Paths turn on and off with the level; sources already on are read
        // now rather than at the next tick.
        Qt.callLater(() => root.tick("all"));
    }

    Component.onCompleted: discovery.running = true

    Process {
        id: discovery

        command: ["sh", "-c", root.discoverScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = root.parseTopo(text);
                if (JSON.stringify(t) !== JSON.stringify(root.topo)) {
                    root.topo = t;
                    root.egpuAwake = t.egpu !== null;
                }
            }
        }
    }

    // Free space has no file; df is run every 10 s while the panel is open.
    Process {
        id: df

        command: ["df", "-B1", "--output=target,size,used", "/", "/home", "/mnt/games"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.raw.df = text;
                commit.restart();
            }
        }
    }

    Instantiator {
        id: views

        model: root.sources

        FileView {
            required property var modelData
            readonly property var src: modelData
            readonly property bool on: root.active(modelData)
            // When a read was last asked for, in ms since the epoch; 0 before
            // the first.
            property real readAt: 0

            // Setting the path reads the file, so a slow source keeps its
            // path once read and only tick() reads it again, when due.
            path: on || (src.rate === "slow" && readAt > 0) ? modelData.file : ""
            printErrors: false
            onOnChanged: if (on && readAt === 0)
                readAt = Date.now()
            Component.onCompleted: if (on)
                readAt = Date.now()
            onLoaded: {
                const value = src.bin ? data() : text();
                root.raw[src.key] = value;
                if (src.key === "egpuStatus")
                    root.egpuAwake = text().trim() === "active";
            }
            onLoadFailed: {
                root.raw[src.key] = null;
                if (src.key === "egpuJuncHw")
                    root.egpuAwake = false;
            }
        }
    }

    Timer {
        interval: root.level === 0 ? 5000 : 1000
        running: root.topo !== null
        repeat: true
        onTriggered: root.tick("fast")
    }

    Timer {
        interval: 10000
        running: root.topo !== null && root.level > 0
        repeat: true
        onTriggered: root.tick("slow")
    }

    // Reads finish on Qt's thread pool within a few ms (NVMe up to ~40 ms);
    // the figures are rebuilt once after them, not per file.
    Timer {
        id: commit

        interval: 150
        onTriggered: root.snapshot()
    }
}
