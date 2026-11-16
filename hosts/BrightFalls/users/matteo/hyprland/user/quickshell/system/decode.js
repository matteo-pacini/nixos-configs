// Pure functions for the system panel: the amdgpu gpu_metrics decoder, the
// /proc and sysfs text parsers, and the figure formatting. No QML here, so
// the same file runs under node for the tests.

// gpu_metrics (drivers/gpu/drm/amd/include/kgd_pp_interface.h). Only the two
// layouts this machine emits are decoded: v1.3 (Navi 21) and v2.1 (Hawk
// Point); any other header gives null rather than misread offsets. 0xFFFF
// marks a field the firmware does not fill.
function u16(view, offset) {
    const v = view.getUint16(offset, true);
    return v === 0xffff ? null : v;
}

function metrics(buffer) {
    if (!buffer || buffer.byteLength < 4)
        return null;
    const view = new DataView(buffer);
    const size = view.getUint16(0, true);
    const format = view.getUint8(2);
    const content = view.getUint8(3);
    if (format === 1 && content === 3 && size >= 120 && buffer.byteLength >= 120) {
        const lo = view.getUint32(112, true);
        const hi = view.getUint32(116, true);
        const unset = lo === 0xffffffff && hi === 0xffffffff;
        return {
            version: "1.3",
            edge: u16(view, 4),
            junction: u16(view, 6),
            mem: u16(view, 8),
            vrGfx: u16(view, 10),
            vrSoc: u16(view, 12),
            vrMem: u16(view, 14),
            gfxActivity: u16(view, 16),
            umcActivity: u16(view, 18),
            socketPower: u16(view, 22),
            gfxClock: u16(view, 54),
            uClock: u16(view, 58),
            fanRpm: u16(view, 72),
            linkWidth: u16(view, 74),
            linkSpeed: u16(view, 76),
            voltSoc: u16(view, 104),
            voltGfx: u16(view, 106),
            voltMem: u16(view, 108),
            throttle: unset ? null : throttleReasons(lo, hi)
        };
    }
    if (format === 2 && content === 1 && size >= 120 && buffer.byteLength >= 120) {
        const cores = [];
        const clocks = [];
        for (let i = 0; i < 8; i++) {
            const t = u16(view, 8 + 2 * i);
            if (t !== null)
                cores.push(t / 100);
            const c = u16(view, 88 + 2 * i);
            if (c !== null)
                clocks.push(c);
        }
        const gfx = u16(view, 4);
        return {
            version: "2.1",
            gfxTemp: gfx === null ? null : gfx / 100,
            coreTemps: cores,
            coreClocks: clocks,
            gfxActivity: u16(view, 28),
            averageGfxClock: u16(view, 64)
        };
    }
    return null;
}

// indep_throttle_status split the way MangoHud does (amdgpu.cpp): bits 0-7
// power, 16-23 current, 32-47 temperature, 56-63 other. MangoHud also drops
// bit 36 (hotspot) because RDNA 3 sets it constantly; on this RDNA 2 card it
// is a real limit and stays in.
function throttleReasons(lo, hi) {
    const out = [];
    if ((hi & 0xffff) !== 0)
        out.push("temperature");
    if ((lo & 0xff) !== 0)
        out.push("power");
    if (((lo >>> 16) & 0xff) !== 0)
        out.push("current");
    if (((hi >>> 24) & 0xff) !== 0)
        out.push("other");
    return out;
}

// /proc/stat: { total: [busy, all], threads: [[busy, all], ...] } in ticks.
// iowait counts as idle: a thread waiting on the disk is not working.
function cpuTimes(text) {
    const out = {
        total: null,
        threads: []
    };
    for (const line of text.split("\n")) {
        const m = line.match(/^cpu(\d*)\s+(.*)$/);
        if (!m)
            continue;
        const f = m[2].trim().split(/\s+/).map(Number);
        const all = f.slice(0, 8).reduce((a, b) => a + b, 0);
        const busy = all - f[3] - f[4];
        if (m[1] === "")
            out.total = [busy, all];
        else
            out.threads[Number(m[1])] = [busy, all];
    }
    return out;
}

// Percent busy between two cpuTimes pairs.
function busyPercent(before, after) {
    if (!before || !after)
        return null;
    const all = after[1] - before[1];
    return all > 0 ? Math.max(0, Math.min(100, (after[0] - before[0]) / all * 100)) : 0;
}

// /proc/meminfo in bytes.
function meminfo(text) {
    const out = {};
    for (const line of text.split("\n")) {
        const m = line.match(/^(\w+(?:\(\w+\))?):\s+(\d+)/);
        if (m)
            out[m[1]] = Number(m[2]) * 1024;
    }
    return out;
}

// The interface carrying the lowest-metric default route in /proc/net/route.
function uplink(text) {
    let best = null;
    for (const line of text.split("\n").slice(1)) {
        const f = line.trim().split(/\s+/);
        if (f.length < 8 || f[1] !== "00000000" || f[7] !== "00000000")
            continue;
        const metric = Number(f[6]);
        if (best === null || metric < best.metric)
            best = {
                name: f[0],
                metric
            };
    }
    return best ? best.name : "";
}

// Received and sent bytes of `iface` from /proc/net/dev, or null.
function netBytes(text, iface) {
    for (const line of text.split("\n")) {
        const m = line.match(/^\s*([^:\s]+):\s*(.*)$/);
        if (m && m[1] === iface) {
            const f = m[2].trim().split(/\s+/).map(Number);
            return [f[0], f[8]];
        }
    }
    return null;
}

// /sys/block/<dev>/stat: bytes read, bytes written, io_ticks ms.
function blockStat(text) {
    const f = text.trim().split(/\s+/).map(Number);
    return f.length >= 10 ? [f[2] * 512, f[6] * 512, f[9]] : null;
}

// `df -B1 --output=target,size,used` lines, without repeats (a path that is
// not mounted reports the filesystem it lives on).
function volumes(text) {
    const seen = {};
    const out = [];
    for (const line of text.split("\n").slice(1)) {
        const f = line.trim().split(/\s+/);
        if (f.length < 3 || seen[f[0]])
            continue;
        seen[f[0]] = true;
        out.push({
            target: f[0],
            size: Number(f[1]),
            used: Number(f[2])
        });
    }
    return out;
}

// "16.0 GT/s PCIe" -> 16.
function gts(text) {
    const m = String(text ?? "").match(/([\d.]+)\s*GT\/s/);
    return m ? Number(m[1]) : null;
}

function pcieGen(speed) {
    return ({
            "2.5": 1,
            "5": 2,
            "8": 3,
            "16": 4,
            "32": 5,
            "64": 6
        })[String(speed)] ?? null;
}

// pp_dpm_pcie: true when the active ("*") level is not the last one, i.e.
// the card itself asked for a slower link to save power.
function linkPowerSaving(text) {
    const lines = String(text ?? "").split("\n").filter(l => /^\d+:/.test(l));
    const active = lines.findIndex(l => /\*\s*$/.test(l));
    return active >= 0 && active < lines.length - 1;
}

// The link line's state: "full", "saving" or "reduced".
function linkState(cur, max, saving) {
    if (cur.speed === null || cur.width === null || max.speed === null || max.width === null)
        return "";
    if (cur.speed >= max.speed && cur.width >= max.width)
        return "full";
    return saving ? "saving" : "reduced";
}

// TOTAL_ERR_* counters of an aer_dev_* file.
function aerTotal(text) {
    const m = String(text ?? "").match(/TOTAL_ERR_\w+\s+(\d+)/);
    return m ? Number(m[1]) : 0;
}

// The fan line from LACT's /etc/lact/config.yaml for `gpuKey`'s PCI address,
// from the YAML subset LACT writes; "" when the file does not mention it.
function lactFan(text, pciAddress) {
    if (!text)
        return "";
    const lines = text.split("\n");
    const start = lines.findIndex(l => l.trim().endsWith(pciAddress + ":"));
    if (start < 0)
        return "";
    const indent = lines[start].search(/\S/);
    let enabled = false;
    let mode = "";
    const curve = [];
    let inCurve = -1;
    for (let i = start + 1; i < lines.length; i++) {
        const l = lines[i];
        if (l.trim() === "")
            continue;
        const at = l.search(/\S/);
        if (at <= indent)
            break;
        if (inCurve >= 0 && at <= inCurve)
            inCurve = -1;
        const kv = l.trim().match(/^([\w.]+):\s*(.*)$/);
        if (!kv)
            continue;
        if (inCurve >= 0)
            curve.push([Number(kv[1]), Number(kv[2])]);
        else if (kv[1] === "fan_control_enabled")
            enabled = kv[2] === "true";
        else if (kv[1] === "mode")
            mode = kv[2];
        else if (kv[1] === "curve" && kv[2] === "")
            inCurve = at;
    }
    if (!enabled)
        return "";
    if (mode === "curve" && curve.length > 0) {
        const a = curve[0];
        const b = curve[curve.length - 1];
        return `LACT curve, ${a[0]} °C ${Math.round(a[1] * 100)}% to ${b[0]} °C ${Math.round(b[1] * 100)}%`;
    }
    return mode === "static" ? "LACT, fixed speed" : "LACT";
}

// 0 normal, 1 warm (orange), 2 hot (red).
function heat(t, warm, hot) {
    if (t === null || t === undefined)
        return 0;
    return t >= hot ? 2 : t >= warm ? 1 : 0;
}

function round1(x) {
    return Math.round(x * 10) / 10;
}

// 9.1e9 -> "8.5" (GiB, one decimal).
function gib(bytes) {
    return String(round1(bytes / 1073741824));
}

// Disk sizes in decimal units, as drives are sold: "77 / 210 GB", "0.47 / 2.99 TB".
function diskPair(used, size) {
    if (size >= 1e12)
        return `${(used / 1e12).toFixed(2)} / ${(size / 1e12).toFixed(2)} TB`;
    return `${Math.round(used / 1e9)} / ${Math.round(size / 1e9)} GB`;
}

function rate(bps) {
    if (bps === null || bps === undefined)
        return "–";
    if (bps >= 1e9)
        return `${round1(bps / 1e9)} GB/s`;
    return `${(bps / 1e6).toFixed(1)} MB/s`;
}

// 4500000 -> "4.5", 5263061 with digits 2 -> "5.26".
function ghz(khz, digits) {
    return String(Number((khz / 1e6).toFixed(digits ?? 1)));
}

if (typeof module !== "undefined")
    module.exports = {
        metrics,
        throttleReasons,
        cpuTimes,
        busyPercent,
        meminfo,
        uplink,
        netBytes,
        blockStat,
        volumes,
        gts,
        pcieGen,
        linkPowerSaving,
        linkState,
        aerTotal,
        lactFan,
        heat,
        gib,
        diskPair,
        rate,
        ghz
    };
