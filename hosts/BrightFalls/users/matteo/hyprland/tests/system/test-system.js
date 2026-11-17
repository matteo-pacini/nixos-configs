// The system panel's library (quickshell/system/decode.js) against invented
// gpu_metrics blobs and /proc, sysfs, df and LACT texts.
// Run: node test-system.js <directory holding decode.js>
const assert = require("node:assert/strict");
const path = require("node:path");
const D = require(path.join(path.resolve(process.argv[2]), "decode.js"));
let n = 0;
const t = (name, f) => {
    try {
        f();
    } catch (e) {
        console.error(`not ok: ${name}`);
        throw e;
    }
    n++;
};

// A gpu_metrics blob: header (size, format, content), then u16 fields at
// the given offsets and u32 pairs for the throttle word.
function blob(size, format, content, u16s, u32s) {
    const buf = new ArrayBuffer(size);
    const v = new DataView(buf);
    v.setUint16(0, size, true);
    v.setUint8(2, format);
    v.setUint8(3, content);
    for (const [off, val] of Object.entries(u16s ?? {}))
        v.setUint16(Number(off), val, true);
    for (const [off, val] of Object.entries(u32s ?? {}))
        v.setUint32(Number(off), val, true);
    return buf;
}

// ---- gpu_metrics ----

const v13 = {
    4: 51, 6: 63, 8: 70, 10: 44, 12: 45, 14: 46, 16: 97, 18: 33, 22: 255,
    54: 2400, 58: 1000, 72: 1650, 74: 16, 76: 4, 104: 900, 106: 1100, 108: 1350
};

t("v1.3 (Navi 21): every field at its offset", () => {
    const m = D.metrics(blob(120, 1, 3, v13, { 112: 0, 116: 0 }));
    assert.deepEqual(m, {
        version: "1.3",
        edge: 51, junction: 63, mem: 70,
        vrGfx: 44, vrSoc: 45, vrMem: 46,
        gfxActivity: 97, umcActivity: 33, socketPower: 255,
        gfxClock: 2400, uClock: 1000, fanRpm: 1650,
        linkWidth: 16, linkSpeed: 4,
        voltSoc: 900, voltGfx: 1100, voltMem: 1350,
        throttle: []
    });
});

t("v1.3: 0xFFFF is an unfilled field, not 65535", () => {
    const m = D.metrics(blob(120, 1, 3, { ...v13, 4: 0xffff, 72: 0xffff }));
    assert.equal(m.edge, null);
    assert.equal(m.fanRpm, null);
    assert.equal(m.junction, 63);
});

t("v1.3: an all-ones throttle word is unset, not every reason", () => {
    const m = D.metrics(blob(120, 1, 3, v13, { 112: 0xffffffff, 116: 0xffffffff }));
    assert.equal(m.throttle, null);
});

t("v1.3: throttle reasons from the word", () => {
    const m = D.metrics(blob(120, 1, 3, v13, { 112: 0x00010001, 116: 0x01000010 }));
    assert.deepEqual(m.throttle, ["temperature", "power", "current", "other"]);
});

t("v1.3: a larger blob still decodes", () => {
    assert.equal(D.metrics(blob(128, 1, 3, v13)).version, "1.3");
});

t("v2.1 (Hawk Point): temperatures in centidegrees, cores without gaps", () => {
    const u = { 4: 4250, 28: 12, 64: 800 };
    for (let i = 0; i < 8; i++) {
        u[8 + 2 * i] = 4000 + 100 * i;
        u[88 + 2 * i] = 3000 + i;
    }
    u[8 + 2 * 3] = 0xffff;
    u[88 + 2 * 7] = 0xffff;
    const m = D.metrics(blob(120, 2, 1, u));
    assert.equal(m.version, "2.1");
    assert.equal(m.gfxTemp, 42.5);
    assert.deepEqual(m.coreTemps, [40, 41, 42, 44, 45, 46, 47]);
    assert.deepEqual(m.coreClocks, [3000, 3001, 3002, 3003, 3004, 3005, 3006]);
    assert.equal(m.gfxActivity, 12);
    assert.equal(m.averageGfxClock, 800);
});

t("v2.1: an unfilled graphics temperature is null", () => {
    assert.equal(D.metrics(blob(120, 2, 1, { 4: 0xffff })).gfxTemp, null);
});

t("other layouts, short blobs and nothing give null", () => {
    assert.equal(D.metrics(blob(120, 1, 4, v13)), null);
    assert.equal(D.metrics(blob(120, 2, 2)), null);
    assert.equal(D.metrics(blob(120, 3, 1)), null);
    // The header claims 120 bytes; the read gave fewer.
    const short = blob(120, 1, 3, v13).slice(0, 100);
    assert.equal(D.metrics(short), null);
    // A header that claims less than the layout needs.
    const small = blob(120, 1, 3, v13);
    new DataView(small).setUint16(0, 100, true);
    assert.equal(D.metrics(small), null);
    assert.equal(D.metrics(new ArrayBuffer(3)), null);
    assert.equal(D.metrics(null), null);
    assert.equal(D.metrics(undefined), null);
});

t("throttle reasons: only the documented bit ranges count", () => {
    assert.deepEqual(D.throttleReasons(0, 0), []);
    assert.deepEqual(D.throttleReasons(0x80, 0), ["power"]);
    assert.deepEqual(D.throttleReasons(0x00800000, 0), ["current"]);
    assert.deepEqual(D.throttleReasons(0, 0x8000), ["temperature"]);
    // Bit 36 (hotspot) is a real limit on RDNA 2.
    assert.deepEqual(D.throttleReasons(0, 1 << 4), ["temperature"]);
    assert.deepEqual(D.throttleReasons(0, 0x80000000), ["other"]);
    // Bits 8-15, 24-31 and 48-55 are none of them.
    assert.deepEqual(D.throttleReasons(0xff00ff00, 0x00ff0000), []);
});

// ---- /proc and sysfs ----

const procStat = `cpu  1000 10 500 8000 400 20 30 40 5 0
cpu0 600 5 300 4000 200 10 15 20 0 0
cpu1 400 5 200 4000 200 10 15 20 0 0
intr 123 4 5
ctxt 999
cpu_not_a_cpu 1 2 3
`;

t("cpuTimes: busy excludes idle and iowait; guest is not counted twice", () => {
    const c = D.cpuTimes(procStat);
    // all = user..steal (first eight); busy = all - idle - iowait.
    assert.deepEqual(c.total, [1600, 10000]);
    assert.deepEqual(c.threads, [[950, 5150], [650, 4850]]);
});

t("cpuTimes: nothing to read", () => {
    assert.deepEqual(D.cpuTimes(""), { total: null, threads: [] });
});

t("busyPercent between two samples, clamped, and without a sample", () => {
    assert.equal(D.busyPercent([100, 1000], [150, 1100]), 50);
    assert.equal(D.busyPercent([100, 1000], [100, 1000]), 0);
    assert.equal(D.busyPercent([100, 1000], [300, 1100]), 100);
    assert.equal(D.busyPercent([300, 1000], [100, 1100]), 0);
    assert.equal(D.busyPercent(null, [1, 2]), null);
    assert.equal(D.busyPercent([1, 2], undefined), null);
});

t("meminfo in bytes, names with brackets kept", () => {
    const m = D.meminfo(`MemTotal:       32000000 kB
MemAvailable:   20000000 kB
Active(anon):     1000 kB
HugePages_Total:       0
garbage line
`);
    assert.equal(m.MemTotal, 32000000 * 1024);
    assert.equal(m.MemAvailable, 20000000 * 1024);
    assert.equal(m["Active(anon)"], 1024000);
    assert.equal(m.HugePages_Total, 0);
    assert.equal(Object.keys(m).length, 4);
});

const route = `Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
wlan0\t00000000\t0102A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0
eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
eth0\t0001A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0
`;

t("uplink: the default route with the lowest metric", () => {
    assert.equal(D.uplink(route), "eth0");
});

t("uplink: a zero-metric route that is not default does not count", () => {
    assert.equal(D.uplink(route.split("\n").filter(l => !l.startsWith("eth0\t0000")).join("\n")), "wlan0");
});

t("uplink: no default route, no header only", () => {
    assert.equal(D.uplink(route.split("\n")[0] + "\n"), "");
    assert.equal(D.uplink(""), "");
});

const netdev = `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  5000      50    0    0    0     0          0         0     5000      50    0    0    0     0       0          0
  eth0:123456789 1000    0    0    0     0          0         0 98765432    900    0    0    0     0       0          0
 eth01: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
`;

t("netBytes: received and sent of one interface, by exact name", () => {
    assert.deepEqual(D.netBytes(netdev, "eth0"), [123456789, 98765432]);
    assert.deepEqual(D.netBytes(netdev, "eth01"), [1, 9]);
    assert.equal(D.netBytes(netdev, "eth"), null);
    assert.equal(D.netBytes(netdev, "wlan0"), null);
});

t("blockStat: sectors to bytes, io_ticks", () => {
    assert.deepEqual(D.blockStat("  100 0 2000 50  300 0 4000 60 0 900 110 0 0 0 0 0 0\n"),
        [2000 * 512, 4000 * 512, 900]);
    assert.equal(D.blockStat("1 2 3"), null);
});

t("volumes: header skipped, a repeated target once", () => {
    const df = `Mounted on        1B-blocks         Used
/              210000000000  77000000000
/mnt/games    2990000000000 470000000000
/              210000000000  77000000000
`;
    assert.deepEqual(D.volumes(df), [
        { target: "/", size: 210e9, used: 77e9 },
        { target: "/mnt/games", size: 2.99e12, used: 4.7e11 }
    ]);
    assert.deepEqual(D.volumes("Mounted on 1B-blocks Used\n"), []);
});

// ---- PCIe link ----

t("gts and pcieGen for every generation", () => {
    assert.equal(D.gts("16.0 GT/s PCIe"), 16);
    assert.equal(D.gts("2.5 GT/s PCIe"), 2.5);
    assert.equal(D.gts("Unknown"), null);
    assert.equal(D.gts(null), null);
    assert.deepEqual([2.5, 5, 8, 16, 32, 64].map(D.pcieGen), [1, 2, 3, 4, 5, 6]);
    assert.equal(D.pcieGen(D.gts("8.0 GT/s PCIe")), 3);
    assert.equal(D.pcieGen(null), null);
    assert.equal(D.pcieGen(4), null);
});

t("linkPowerSaving: the active level below the top one", () => {
    const top = "0: 2.5GT/s, x1 310Mhz\n1: 16.0GT/s, x16 619Mhz *\n";
    const low = "0: 2.5GT/s, x1 310Mhz *\n1: 16.0GT/s, x16 619Mhz\n";
    assert.equal(D.linkPowerSaving(top), false);
    assert.equal(D.linkPowerSaving(low), true);
    assert.equal(D.linkPowerSaving("0: 2.5GT/s, x1 310Mhz\n"), false);
    assert.equal(D.linkPowerSaving(""), false);
    assert.equal(D.linkPowerSaving(undefined), false);
});

t("linkState: full, saving, reduced, unknown", () => {
    const max = { speed: 16, width: 16 };
    assert.equal(D.linkState({ speed: 16, width: 16 }, max, false), "full");
    assert.equal(D.linkState({ speed: 2.5, width: 16 }, max, true), "saving");
    assert.equal(D.linkState({ speed: 16, width: 4 }, max, false), "reduced");
    assert.equal(D.linkState({ speed: 8, width: 16 }, max, false), "reduced");
    assert.equal(D.linkState({ speed: null, width: 16 }, max, false), "");
    assert.equal(D.linkState({ speed: 16, width: 16 }, { speed: 16, width: null }, false), "");
});

t("aerTotal: the TOTAL_ERR counter, 0 when absent", () => {
    assert.equal(D.aerTotal("RxErr 2\nBadTLP 1\nTOTAL_ERR_COR 3\n"), 3);
    assert.equal(D.aerTotal("Undefined 0\nTOTAL_ERR_FATAL 0\n"), 0);
    assert.equal(D.aerTotal(""), 0);
    assert.equal(D.aerTotal(null), 0);
});

// ---- LACT ----

const lact = `daemon:
  log_level: info
apply_settings_timer: 5
gpus:
  1002:0000-0000:0000-0000:0a:00.0:
    fan_control_enabled: false
    fan_control_settings:
      mode: static
  1002:0000-0000:0000-0000:03:00.0:
    fan_control_enabled: true
    fan_control_settings:
      mode: curve
      static_speed: 0.5
      temperature_key: edge
      curve:
        40: 0.2
        60: 0.35
        80: 0.8
      spindown_delay_ms: 0
    power_cap: 250.0
current_profile: null
`;

t("lactFan: a curve, first and last points", () => {
    assert.equal(D.lactFan(lact, "0000:03:00.0"), "LACT curve, 40 °C 20% to 80 °C 80%");
});

t("lactFan: fan control off for that card", () => {
    assert.equal(D.lactFan(lact, "0000:0a:00.0"), "");
});

t("lactFan: a card the file does not mention, no file", () => {
    assert.equal(D.lactFan(lact, "0000:05:00.0"), "");
    assert.equal(D.lactFan("", "0000:03:00.0"), "");
    assert.equal(D.lactFan(null, "0000:03:00.0"), "");
});

t("lactFan: static, and a curve mode with no points", () => {
    const s = lact.replace("mode: curve", "mode: static");
    assert.equal(D.lactFan(s, "0000:03:00.0"), "LACT, fixed speed");
    const empty = lact.replace(/      curve:\n(        .*\n)+/, "");
    assert.equal(D.lactFan(empty, "0000:03:00.0"), "LACT");
});

t("lactFan: another card's settings do not leak into this one", () => {
    // The card after the one asked about has a curve; this one has none.
    const two = `gpus:
  1002:0000-0000:0000-0000:03:00.0:
    fan_control_enabled: true
    fan_control_settings:
      mode: static
  1002:0000-0000:0000-0000:0a:00.0:
    fan_control_enabled: true
    fan_control_settings:
      mode: curve
      curve:
        30: 0.1
`;
    assert.equal(D.lactFan(two, "0000:03:00.0"), "LACT, fixed speed");
});

// ---- figures ----

t("heat levels at the thresholds", () => {
    assert.equal(D.heat(null, 70, 85), 0);
    assert.equal(D.heat(undefined, 70, 85), 0);
    assert.equal(D.heat(69.9, 70, 85), 0);
    assert.equal(D.heat(70, 70, 85), 1);
    assert.equal(D.heat(85, 70, 85), 2);
    assert.equal(D.heat(0, -1, 5), 1);
});

t("gib, diskPair, rate, ghz", () => {
    assert.equal(D.gib(9.1e9), "8.5");
    assert.equal(D.gib(0), "0");
    assert.equal(D.gib(32 * 1073741824), "32");
    assert.equal(D.diskPair(77e9, 210e9), "77 / 210 GB");
    assert.equal(D.diskPair(0.47e12, 2.99e12), "0.47 / 2.99 TB");
    assert.equal(D.diskPair(5e11, 1e12), "0.50 / 1.00 TB");
    assert.equal(D.rate(null), "–");
    assert.equal(D.rate(undefined), "–");
    assert.equal(D.rate(0), "0.0 MB/s");
    assert.equal(D.rate(12.34e6), "12.3 MB/s");
    assert.equal(D.rate(999.9e6), "999.9 MB/s");
    assert.equal(D.rate(2.34e9), "2.3 GB/s");
    assert.equal(D.ghz(4500000), "4.5");
    assert.equal(D.ghz(4000000), "4");
    assert.equal(D.ghz(5263061, 2), "5.26");
});

// ---- when a read is due ----

t("a slow source is due 10 s after it was last read, never sooner", () => {
    assert.equal(D.due(0, 5000, "slow"), true, "never read");
    assert.equal(D.due(100000, 100000, "slow"), false, "just read");
    assert.equal(D.due(100000, 109999, "slow"), false, "a millisecond early");
    assert.equal(D.due(100000, 110000, "slow"), true, "10 s on");
    assert.equal(D.due(100000, 250000, "slow"), true, "long after");
});

t("other sources are always due", () => {
    assert.equal(D.due(100000, 100000, "fast"), true);
    assert.equal(D.due(100000, 100001, "once"), true);
});

console.log(`ok: ${n} tests`);
