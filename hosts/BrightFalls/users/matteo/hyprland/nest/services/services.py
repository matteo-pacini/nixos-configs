#!/usr/bin/env python3
"""desk-nest's stand-in services: what a --demo nest runs in place of the
machine's own, inside the sandbox only. One program chosen by its first
argument; bin/nest-services links here. README.md, "Recording a tour".

  nest-services sys-seed <dir>   on the host, at up --demo: writes the
                                 invented sysfs/procfs tree the launcher
                                 binds over the real paths (sys_binds)
  nest-services start            inside, before the shell: starts every
                                 stand-in and returns once they answer
  nest-services system           inside (started by start): rewrites the
                                 tree's changing files once a second, for
                                 the state control/system names

Environment: NEST_STATE (the nest's state directory) and NEST_FIXTURES, as
for nest/fakes. Everything shown is invented: an APU with six cores, an
external card, two memory modules, one NVMe drive.
"""
import json
import math
import os
import struct
import subprocess
import sys
import threading
import time

STATE = os.environ.get("NEST_STATE") or "/nonexistent"
HERE = os.path.dirname(os.path.realpath(__file__))


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} nest-services: {msg}", flush=True)


def control(panel, default):
    try:
        with open(os.path.join(STATE, "control", panel)) as f:
            return f.read().strip() or default
    except OSError:
        return default


# ---- system: the invented machine -------------------------------------------

# Where each part of the tree is bound inside the sandbox; desk-nest.sh's
# sandbox_cmd binds the same list (`nest-services sys-binds`). The devices
# live over the PCI host bridge's own directory, which nothing in the nest
# reads (Mesa finds the GPUs through /sys/dev/char), so their paths have the
# /sys/devices/pci… shape the panel reads a PCIe link from.
DEV = "/sys/devices/pci0000:00/0000:00:00.0"
BINDS = [
    ("devices", DEV),
    ("hwmon", "/sys/class/hwmon"),
    ("amdgpu", "/sys/bus/pci/drivers/amdgpu"),
    ("drm", "/sys/class/drm"),
    ("block", "/sys/block"),
    ("cpu", "/sys/devices/system/cpu"),
    ("proc/stat", "/proc/stat"),
    ("proc/meminfo", "/proc/meminfo"),
    ("proc/loadavg", "/proc/loadavg"),
    ("proc/cpuinfo", "/proc/cpuinfo"),
    ("lact", "/etc/lact"),
    ("asound", "/proc/asound"),
    ("net", "/sys/class/net"),
]
EGPU = "0000:03:00.0"
IGPU = "0000:0c:00.0"
NVME = "0000:02:00.0/nvme/nvme0"
THREADS = 12
MODEL = "AMD Ryzen 5 8600G w/ Radeon 760M Graphics"
GIB = 1024 ** 3

# Per state: the figures each file is made from. Temperatures in °C, loads
# in percent, power in W, clocks in MHz, memory in GiB.
STATES = {
    "demo-idle": dict(cpu=41, cpu_load=4, cores=(38, 44), clock=2100, pkg=14, igpu_t=37, igpu_load=3,
                      edge=39, junc=44, mem_t=48, vr=36, g_load=2, g_power=11, g_clock=500, u_clock=96,
                      fan=0, pwm=0, vram=1.1, ram=7.4, dimm=38, nvme=37, load=0.31, disk=(0.4, 0.2, 1),
                      net=(0.02, 0.01), throttle=0),
    "demo-busy": dict(cpu=72, cpu_load=63, cores=(68, 77), clock=4300, pkg=71, igpu_t=55, igpu_load=12,
                      edge=68, junc=83, mem_t=76, vr=61, g_load=97, g_power=236, g_clock=2290, u_clock=1000,
                      fan=1620, pwm=112, vram=11.6, ram=19.8, dimm=49, nvme=51, load=6.8, disk=(1150, 42, 61),
                      net=(48.0, 1.9), throttle=0),
    "demo-hot": dict(cpu=89, cpu_load=88, cores=(86, 91), clock=4500, pkg=88, igpu_t=71, igpu_load=18,
                     edge=79, junc=95, mem_t=88, vr=78, g_load=99, g_power=254, g_clock=2190, u_clock=1000,
                     fan=2650, pwm=190, vram=14.2, ram=26.1, dimm=58, nvme=66, load=11.4, disk=(820, 310, 74),
                     net=(92.0, 6.5), throttle=0),
}
DEFAULT_STATE = "demo-idle"

# The shell's wall clock runs at this fraction of real time (`clock`), so a
# rate it works out from two samples is bytes over slowed seconds: byte
# counters grow by the slowed time to show the real rates. CPU load is
# ticks over ticks and needs no scaling.
CLOCK_RATE = 0.01


def wobble(t, period, amount, phase=0.0):
    return amount * math.sin(2 * math.pi * (t / period) + phase)


def gpu_metrics_v13(s, t):
    """gpu_metrics v1.3, as an RDNA 2 card writes it (decode.js metrics)."""
    b = bytearray(b"\xff" * 120)
    struct.pack_into("<HBB", b, 0, 120, 1, 3)
    j = s["junc"] + wobble(t, 7, 1.5)
    vals = {4: s["edge"] + wobble(t, 9, 1), 6: j, 8: s["mem_t"], 10: s["vr"], 12: s["vr"] - 4, 14: s["vr"] - 2,
            16: max(0, min(100, s["g_load"] + wobble(t, 3, 2))), 18: s["g_load"] // 2,
            22: s["g_power"] + wobble(t, 2, 3), 54: s["g_clock"] + wobble(t, 4, 15),
            58: s["u_clock"], 72: s["fan"] + (wobble(t, 6, 20) if s["fan"] else 0), 74: 16, 76: 4,
            104: 1000 if s["g_load"] > 50 else 750, 106: 1050 if s["g_load"] > 50 else 700, 108: 1350}
    for off, v in vals.items():
        struct.pack_into("<H", b, off, int(round(v)))
    struct.pack_into("<II", b, 112, s["throttle"], 0)
    return bytes(b)


def gpu_metrics_v21(s, t):
    """gpu_metrics v2.1, as the APU writes it: centi-degrees, six cores."""
    b = bytearray(b"\xff" * 120)
    struct.pack_into("<HBB", b, 0, 120, 2, 1)
    struct.pack_into("<H", b, 4, int((s["igpu_t"] + wobble(t, 8, 0.6)) * 100))
    lo, hi = s["cores"]
    for i in range(6):
        c = lo + (hi - lo) * ((i * 37) % 6) / 5 + wobble(t, 5 + i, 1.2, i)
        struct.pack_into("<H", b, 8 + 2 * i, int(c * 100))
        struct.pack_into("<H", b, 88 + 2 * i, int(s["clock"] + wobble(t, 3 + i, 60, i)))
    struct.pack_into("<H", b, 28, int(s["igpu_load"]))
    struct.pack_into("<H", b, 64, 800 if s["igpu_load"] < 10 else 1600)
    return bytes(b)


class Counters:
    """The ever-growing counters of /proc/stat, the disk and the network."""

    def __init__(self):
        self.threads = [[11_000_000 + 9_000 * i, 1_000_000 + 700 * i] for i in range(THREADS)]  # [idle, busy]
        self.disk = [41_000_000, 23_000_000, 9_800_000]  # sectors read, written, io ms
        self.at = None

    def step(self, s, t):
        dt = 1.0 if self.at is None else max(0.0, min(5.0, t - self.at))
        self.at = t
        for i, c in enumerate(self.threads):
            load = max(0.0, min(100.0, s["cpu_load"] + wobble(t, 4 + i % 5, 6, i)))
            ticks = 100 * dt
            c[1] += int(ticks * load / 100)
            c[0] += int(ticks * (100 - load) / 100)
        r, w, busy = s["disk"]
        slow = dt * CLOCK_RATE
        self.disk[0] += int((r + wobble(t, 5, r * 0.08)) * 1e6 * slow / 512)
        self.disk[1] += int((w + wobble(t, 6, w * 0.1)) * 1e6 * slow / 512)
        # io_ticks are ms of the disk being busy, over the same slowed time.
        self.disk[2] += int(busy * 10 * slow)


def proc_stat(c):
    lines = []
    tot = [sum(x[1] for x in c.threads), sum(x[0] for x in c.threads)]
    # user nice system idle iowait irq softirq steal
    lines.append("cpu  %d 120 %d %d 900 0 400 0 0 0" % (tot[0] * 4 // 5, tot[0] // 5, tot[1]))
    for i, (idle, busy) in enumerate(c.threads):
        lines.append("cpu%d %d 10 %d %d 75 0 33 0 0 0" % (i, busy * 4 // 5, busy // 5, idle))
    lines += ["intr 0", "ctxt 1846253961", "btime 1795564800", "processes 412771", "procs_running 2",
              "procs_blocked 0", "softirq 0"]
    return "\n".join(lines) + "\n"


def meminfo(s, t):
    total = 31_997_004
    used = int((s["ram"] + wobble(t, 11, 0.05)) * GIB / 1024)
    avail = total - used
    rows = [("MemTotal", total), ("MemFree", avail // 3), ("MemAvailable", avail), ("Buffers", 412_300),
            ("Cached", avail // 2), ("SwapCached", 0), ("Shmem", 905_112), ("SwapTotal", 8_388_604),
            ("SwapFree", 8_388_604)]
    return "".join("%-15s %8d kB\n" % (k + ":", v) for k, v in rows)


def cpuinfo():
    out = []
    for i in range(THREADS):
        out.append(f"processor\t: {i}\nvendor_id\t: AuthenticAMD\ncpu family\t: 25\nmodel\t\t: 117\n"
                   f"model name\t: {MODEL}\nstepping\t: 2\ncpu MHz\t\t: 4300.000\ncache size\t: 1024 KB\n"
                   f"physical id\t: 0\nsiblings\t: {THREADS}\ncore id\t\t: {i // 2}\ncpu cores\t: {THREADS // 2}\n")
    return "\n".join(out) + "\n"


def write(path, data, link=None, in_place=False):
    """Writes a file so that a reader never sees it missing or half done:
    by rename, or for a file bound on its own (in_place: /proc/stat and the
    like, where a rename would leave the old file under the bind) by one
    write and a truncate. A link is made once and left alone: discovery
    resolves them while this runs."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if link is not None:
        if not (os.path.islink(path) and os.readlink(path) == link):
            tmp = f"{path}.new"
            if os.path.lexists(tmp):
                os.remove(tmp)
            os.symlink(link, tmp)
            os.replace(tmp, path)
        return
    if isinstance(data, str):
        data = data.encode()
    if in_place:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT, 0o644)
        try:
            os.write(fd, data)
            os.ftruncate(fd, len(data))
        finally:
            os.close(fd)
        return
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return
    except OSError:
        pass
    tmp = f"{path}.new"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def sys_files(s, t, c):
    """{relative path: bytes, str or ("link", target)} for the whole tree."""
    f = {}
    e = f"devices/{EGPU}"
    i = f"devices/{IGPU}"
    # The eGPU.
    f[f"{e}/gpu_metrics"] = gpu_metrics_v13(s, t)
    f[f"{e}/power/runtime_status"] = "active\n"
    f[f"{e}/mem_info_vram_used"] = "%d\n" % int((s["vram"] + wobble(t, 9, 0.03)) * GIB)
    f[f"{e}/mem_info_vram_total"] = "%d\n" % (16 * GIB)
    f[f"{e}/device"] = "0x73bf\n"
    f[f"{e}/revision"] = "0xc1\n"
    f[f"{e}/pp_dpm_pcie"] = "0: 2.5GT/s, x1 310Mhz\n1: 16.0GT/s, x16 619Mhz *\n"
    f[f"{e}/current_link_speed"] = "16.0 GT/s PCIe\n"
    f[f"{e}/current_link_width"] = "16\n"
    for a, k in (("correctable", "COR"), ("nonfatal", "NONFATAL"), ("fatal", "FATAL")):
        f[f"{e}/aer_dev_{a}"] = f"TOTAL_ERR_{k} 0\n"
    f[f"{e}/drm/card1-DP-1/status"] = "connected\n"
    f[f"{e}/drm/card1-DP-1/enabled"] = "enabled\n"
    f[f"{e}/drm/card1-DP-2/status"] = "connected\n"
    f[f"{e}/drm/card1-DP-2/enabled"] = "enabled\n"
    f[f"{e}/drm/card1-HDMI-A-1/status"] = "disconnected\n"
    f[f"{e}/drm/card1-HDMI-A-1/enabled"] = "disabled\n"
    # The port the card hangs off: the host bridge's directory itself.
    f["devices/max_link_speed"] = "16.0 GT/s PCIe\n"
    f["devices/max_link_width"] = "16\n"
    # The APU's graphics.
    f[f"{i}/gpu_metrics"] = gpu_metrics_v21(s, t)
    f[f"{i}/gpu_busy_percent"] = "%d\n" % s["igpu_load"]
    f[f"{i}/mem_info_vram_used"] = "%d\n" % int(0.31 * GIB)
    f[f"{i}/mem_info_vram_total"] = "%d\n" % (2 * GIB)
    f[f"{i}/drm/card2-HDMI-A-2/status"] = "disconnected\n"
    f[f"{i}/drm/card2-HDMI-A-2/enabled"] = "disabled\n"
    f["amdgpu/" + EGPU] = ("link", f"{DEV}/{EGPU}")
    f["amdgpu/" + IGPU] = ("link", f"{DEV}/{IGPU}")
    for card, gpu, conns in (("card1", EGPU, ("DP-1", "DP-2", "HDMI-A-1")), ("card2", IGPU, ("HDMI-A-2",))):
        for n in conns:
            f[f"drm/{card}-{n}"] = ("link", f"{DEV}/{gpu}/drm/{card}-{n}")
    # hwmon: one directory per sensor chip, `device` naming its device.
    hw = [
        ("k10temp", "0000:00:18.3", {"temp1_input": s["cpu"] + wobble(t, 6, 0.8)}),
        ("amdgpu", EGPU, {"temp1_input": s["edge"] + wobble(t, 9, 1), "temp2_input": s["junc"] + wobble(t, 7, 1.5),
                          "temp3_input": s["mem_t"], "temp1_crit": 100, "temp2_crit": 110, "temp3_crit": 100}),
        ("amdgpu", IGPU, {}),
        ("spd5118", "i2c-0/0-0051", {"temp1_input": s["dimm"] + wobble(t, 13, 0.3), "temp1_max": 55, "temp1_crit": 85}),
        ("spd5118", "i2c-0/0-0053", {"temp1_input": s["dimm"] + 1 + wobble(t, 12, 0.3), "temp1_max": 55, "temp1_crit": 85}),
        ("nvme", NVME, {"temp1_input": s["nvme"] + wobble(t, 17, 0.4), "temp1_max": 81.85}),
    ]
    for n, (name, dev, temps) in enumerate(hw):
        d = f"hwmon/hwmon{n}"
        f[f"{d}/name"] = name + "\n"
        f[f"{d}/device"] = ("link", f"{DEV}/{dev}")
        f[f"devices/{dev}/.keep"] = ""
        for k, v in temps.items():
            f[f"{d}/{k}"] = "%d\n" % int(round(v * 1000))
    eg, ig = "hwmon/hwmon1", "hwmon/hwmon2"
    f[f"{eg}/pwm1"] = "%d\n" % s["pwm"]
    f[f"{eg}/pwm1_enable"] = "2\n"
    f[f"{eg}/power1_cap"] = "%d\n" % (255 * 1_000_000)
    f[f"{ig}/power1_average"] = "%d\n" % int((s["pkg"] + wobble(t, 3, 1.5)) * 1_000_000)
    f[f"{ig}/freq1_input"] = "%d\n" % int((800 if s["igpu_load"] < 10 else 1600) * 1_000_000)
    f[f"{ig}/in0_input"] = "%d\n" % (1015 if s["cpu_load"] > 40 else 862)
    f[f"{ig}/in1_input"] = "%d\n" % 1003
    # The drive.
    blk = f"devices/{NVME}/nvme0n1"
    r, w, busy = c.disk
    f[f"{blk}/stat"] = "%8d 0 %d 0 %8d 0 %d 0 0 %d 0\n" % (r // 8, r, w // 8, w, busy)
    f[f"{blk}/size"] = "%d\n" % (2_000_398_934_016 // 512)
    f["block/nvme0n1"] = ("link", f"{DEV}/{NVME}/nvme0n1")
    # The CPU.
    f["cpu/online"] = f"0-{THREADS - 1}\n"
    f["cpu/possible"] = f"0-{THREADS - 1}\n"
    f["cpu/present"] = f"0-{THREADS - 1}\n"
    for n in range(THREADS):
        cf = f"cpu/cpu{n}/cpufreq"
        f[f"{cf}/scaling_cur_freq"] = "%d\n" % int((s["clock"] + wobble(t, 2 + n % 4, 90, n)) * 1000)
        f[f"{cf}/cpuinfo_max_freq"] = "5000000\n"
        f[f"{cf}/scaling_max_freq"] = "4500000\n"
        f[f"{cf}/scaling_governor"] = "powersave\n"
        f[f"{cf}/energy_performance_preference"] = "balance_performance\n"
    f["proc/stat"] = proc_stat(c)
    f["proc/meminfo"] = meminfo(s, t)
    f["proc/loadavg"] = "%.2f %.2f %.2f 2/1187 412771\n" % (s["load"] + wobble(t, 20, 0.1), s["load"] * 0.9, s["load"] * 0.7)
    f["proc/cpuinfo"] = cpuinfo()
    # The network panel reads the wired link's duplex here.
    f["net/enp2s0/duplex"] = "full\n"
    f["net/enp2s0/speed"] = "1000\n"
    f["lact/config.yaml"] = (
        "version: 5\ndaemon:\n  log_level: info\ngpus:\n"
        f"  1002:73BF-1EAE:6801-{EGPU}:\n    fan_control_enabled: true\n    fan_control_settings:\n"
        "      mode: curve\n      static_speed: 0.5\n      temperature_key: junction\n      interval_ms: 500\n"
        "      curve:\n        40: 0.2\n        55: 0.35\n        70: 0.5\n        85: 0.75\n        95: 1.0\n")
    return f


# The parts bound file by file, written in place.
SINGLE_FILES = {rel for rel, _ in BINDS if rel.startswith("proc/")}


def write_tree(root, s, t, c, playing):
    files = sys_files(s, t, c)
    files.update(asound_files(playing))
    for rel, v in files.items():
        if isinstance(v, tuple):
            write(os.path.join(root, rel), None, link=v[1])
        else:
            write(os.path.join(root, rel), v, in_place=rel in SINGLE_FILES)


def sys_root():
    return os.path.join(STATE, "home", "sys")


def sys_seed(root):
    c = Counters()
    write_tree(root, STATES[DEFAULT_STATE], time.time(), c, True)
    demo_home(os.path.dirname(root))


# Speed tests the network panel lists as run before the demo's 09:41, and
# the computer's name in the "Set in Nix" rows: the one the demo's fleet
# gives it.
DEMO_HOSTNAME = "Kestrel"
SPEEDTESTS = [
    ("2026-11-24T18:05:12Z", "Wired connection 1", "enp2s0", 912.4, 486.7, 7.8, "cloudflare"),
    ("2026-11-25T08:16:40Z", "Harbour", "wlan0", 412.6, 198.3, 14.2, "speedtest"),
    ("2026-11-25T08:58:03Z", "Wired connection 1", "enp2s0", 938.1, 502.9, 6.9, "cloudflare"),
]


def demo_home(home):
    """On the host at up --demo, after the homes are seeded: speed-test
    history, and the real host's name in the seeded locked.json files."""
    tools = {"cloudflare": "cfspeedtest", "speedtest": "speedtest"}
    write(os.path.join(home, "state", "desk", "speedtests.jsonl"), "".join(
        json.dumps({"at": at, "connection": conn, "interface": iface, "download_mbps": down, "upload_mbps": up,
                    "ping_ms": ping, "provider": prov, "tool": tools[prov]}) + "\n"
        for at, conn, iface, down, up, ping, prov in SPEEDTESTS))
    desk = os.path.join(home, "data", "desk")
    for area in sorted(os.listdir(desk)) if os.path.isdir(desk) else []:
        path = os.path.join(desk, area, "locked.json")
        if os.path.isfile(path):
            with open(path) as f:
                text = f.read()
            write(path, text.replace("BrightFalls", DEMO_HOSTNAME))


def sys_binds():
    for rel, dest in BINDS:
        print(rel, dest)


def system():
    root = sys_root()
    c = Counters()
    cur = None
    while True:
        name = control("system", DEFAULT_STATE)
        if name != cur:
            log(f"system: {name}")
            cur = name
        s = STATES.get(name, STATES[DEFAULT_STATE])
        try:
            playing = AUDIO_STATES.get(control("audio", AUDIO_DEFAULT), AUDIO_STATES[AUDIO_DEFAULT])[0]
            write_tree(root, s, time.time(), c, playing)
        except OSError as e:
            log(f"system: {e}")
        c.step(s, time.time())
        time.sleep(1)


# ---- audio: a private PipeWire ---------------------------------------------------

# The outputs and the input, as null nodes of the nest's own PipeWire. The
# first output carries the name the audio panel knows the DAC stack by
# (Audio.qml modiNode) and the ALSA card number its /proc/asound files are
# read from (asound_files, bound over /proc/asound).
MODI = "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo"
SPEAKERS = "alsa_output.pci-0000_0c_00.6.analog-stereo"
MIC = "alsa_input.usb-Desk_Microphone-00.analog-stereo"
MODI_CARD = 1
AUDIO_DEFAULT = "demo-playing"
# control/audio: whether the tune plays, and on which output.
AUDIO_STATES = {"demo-playing": (True, MODI), "demo-speakers": (True, SPEAKERS), "demo-quiet": (False, MODI)}

# The outputs are null sinks. The microphone is PipeWire's test tone: a null
# node classed as a source has no capture side, and a level monitor on it
# fails to start ("Operation not supported").
PIPEWIRE_CONF = """\
# desk-nest --demo: the invented outputs and input (nest/services).
context.spa-libs = { audiotestsrc = audiotestsrc/libspa-audiotestsrc }
context.objects = [
%s
]
""" % "\n".join(
    "    { factory = adapter args = { factory.name = %s node.name = \"%s\"\n"
    "        node.description = \"%s\" media.class = \"%s\" audio.position = [ FL FR ]\n"
    "        monitor.channel-volumes = true priority.session = %d priority.driver = %d%s } }"
    % (factory, name, desc, cls, prio, prio, extra)
    for factory, name, desc, cls, prio, extra in (
        ("support.null-audio-sink", MODI, "Modi 2", "Audio/Sink", 1100, " alsa.card = %d" % MODI_CARD),
        ("support.null-audio-sink", SPEAKERS, "Desk Speakers", "Audio/Sink", 1000, ""),
        ("audiotestsrc", MIC, "Desk Microphone", "Audio/Source", 1000, " node.param.Props = { live = true }"),
    ))

# No hardware: no ALSA, Bluetooth or camera monitors (the nest has no
# /dev/snd, and its system bus holds only the demo's stand-ins); no logind,
# portal or reserve-device; nothing remembered between runs.
WIREPLUMBER_CONF = """\
wireplumber.profiles = {
  desk-nest-demo = {
    inherits = [ main, mixin.systemwide-session, mixin.stateless ]
    hardware.audio = disabled
    hardware.bluetooth = disabled
    hardware.video-capture = disabled
  }
}
"""


def real(cmd):
    """`cmd` from PATH, skipping desk-nest's fakes and stubs."""
    fakes = os.path.join(os.path.dirname(HERE), "fakes", "bin")
    for d in os.environ.get("PATH", "").split(":"):
        p = os.path.join(d, cmd)
        if d and os.path.realpath(d) != os.path.realpath(fakes) and os.access(p, os.X_OK):
            return p
    raise FileNotFoundError(cmd)


def asound_files(playing):
    """The DAC's ALSA card as /proc/asound shows it (audio/Modi.qml)."""
    stream = ["Schiit Audio Schiit Modi 2 at usb-0000:0c:00.3-2, high speed : USB Audio", "", "Playback:",
              "  Status: %s" % ("Running" if playing else "Stop")]
    for alt, (fmt, bits) in enumerate((("S16_LE", 16), ("S24_3LE", 24), ("S32_LE", 32)), 1):
        stream += [f"  Interface 1", f"    Altset {alt}", f"    Format: {fmt}", "    Channels: 2",
                   "    Endpoint: 0x01 (1 OUT) (ASYNC)", "    Rates: 44100, 48000, 88200, 96000, 176400, 192000",
                   f"    Bits: {bits}", ""]
    params = ("access: MMAP_INTERLEAVED\nformat: S32_LE\nsubformat: STD\nchannels: 2\nrate: 48000 (48000/1)\n"
              "period_size: 1024\nbuffer_size: 8192\n") if playing else "closed\n"
    c = f"asound/card{MODI_CARD}"
    return {"asound/cards": f" {MODI_CARD} [Modi           ]: USB-Audio - Schiit Modi 2\n",
            f"{c}/stream0": "\n".join(stream) + "\n", f"{c}/pcm0p/sub0/hw_params": params,
            f"{c}/id": "Modi\n"}


def tone():
    """An endless soft tune, s16 stereo at 48 kHz on stdout: a slow chord
    progression with a plucked pulse, so a level meter moves."""
    rate, step = 48000, 4800
    chords = [(220.0, 277.18, 329.63), (196.0, 246.94, 293.66), (174.61, 220.0, 261.63), (196.0, 246.94, 329.63)]
    n = 0
    out = sys.stdout.buffer
    while True:
        buf = bytearray()
        for i in range(n, n + step):
            t = i / rate
            chord = chords[int(t / 2.4) % len(chords)]
            beat = (t * 2) % 1.0
            env = 0.35 + 0.65 * math.exp(-beat * 5)
            v = sum(math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t) for f in chord)
            s = int(max(-1.0, min(1.0, 0.17 * env * v)) * 32767)
            pan = 0.1 * math.sin(2 * math.pi * t / 7)
            buf += struct.pack("<hh", int(s * (1 - pan)), int(s * (1 + pan)))
        n += step
        try:
            out.write(buf)
            out.flush()
        except BrokenPipeError:
            return


def wait_for(what, check, seconds=10):
    for _ in range(int(seconds * 10)):
        if check():
            return True
        time.sleep(0.1)
    log(f"{what}: not ready after {seconds} s")
    return False


def pw_nodes():
    try:
        out = subprocess.run([real("pw-dump")], capture_output=True, text=True, timeout=5).stdout
        return json.loads(out or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []


def node_id(name):
    for o in pw_nodes():
        if o.get("type") == "PipeWire:Interface:Node" and (o.get("info", {}).get("props", {}).get("node.name") == name):
            return o["id"]
    return None


def mic_voice():
    """Moves the microphone's level like someone talking calmly: syllables,
    short dips between words, a pause now and then. It sets the test tone's
    own volume, v, which gives a sample peak of about v squared; the panel
    shows the cube root of the peak and marks 0.99 as clipping, so v from
    0.06 to 0.40 reads 0.15 to 0.54 on its meter."""
    import random
    i = node_id(MIC)
    if i is None:
        log("audio: no microphone to move")
        return
    cli = subprocess.Popen([real("pw-cli")], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, text=True)
    rng = random.Random(941)
    level = 0.06

    def say(target, seconds):
        nonlocal level
        steps = max(1, int(seconds / 0.08))
        for _ in range(steps):
            level += (target - level) * 0.5
            cli.stdin.write(f"set-param {i} Props {{ volume = {min(0.40, max(0.04, level)):.3f} }}\n")
            cli.stdin.flush()
            time.sleep(0.08)

    try:
        while True:
            for _ in range(rng.randint(3, 9)):
                for _ in range(rng.randint(1, 3)):
                    say(rng.uniform(0.24, 0.40), rng.uniform(0.10, 0.24))
                    say(rng.uniform(0.14, 0.22), rng.uniform(0.05, 0.10))
                say(0.10, rng.uniform(0.08, 0.20))
            say(0.06, rng.uniform(0.5, 1.4))
    except (BrokenPipeError, OSError) as e:
        log(f"audio: the microphone's level stopped: {e}")


def audio():
    """PipeWire and WirePlumber, then the tune, kept to control/audio."""
    cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ["HOME"], ".config")
    # A config directory of its own: PipeWire would otherwise also read the
    # host's /etc/pipewire (this machine's own filter chains and rates).
    pw_dir = f"{cfg}/pipewire-demo"
    with open(os.path.join(os.path.dirname(os.path.realpath(real("pipewire"))), "..", "share", "pipewire",
                           "pipewire.conf")) as f:
        main_conf = f.read()
    for path, text in ((f"{pw_dir}/pipewire.conf", main_conf),
                       (f"{pw_dir}/pipewire.conf.d/desk-nest-demo.conf", PIPEWIRE_CONF),
                       (f"{cfg}/wireplumber/wireplumber.conf.d/desk-nest-demo.conf", WIREPLUMBER_CONF)):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
    sock = os.path.join(os.environ["XDG_RUNTIME_DIR"], "pipewire-0")
    out = dict(stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stdout)
    subprocess.Popen([real("pipewire")], env=dict(os.environ, PIPEWIRE_CONFIG_DIR=pw_dir), **out)
    wait_for("pipewire", lambda: os.path.exists(sock))
    subprocess.Popen([real("wireplumber"), "--profile", "desk-nest-demo"], **out)
    wait_for("the outputs", lambda: None not in (node_id(MODI), node_id(SPEAKERS)))
    # Below full, so a step up shows on the OSD.
    # The microphone at full gain: the panel's meter divides a node's own
    # volume back out (Quickshell peak.cpp), so its level is set at the
    # source instead (mic_voice).
    for name, vol in ((MODI, "0.62"), (SPEAKERS, "0.45"), (MIC, "1.0")):
        i = node_id(name)
        if i is not None:
            subprocess.run([real("wpctl"), "set-volume", str(i), vol], **out)
    threading.Thread(target=mic_voice, daemon=True).start()
    player = None
    cur = None
    while True:
        name = control("audio", AUDIO_DEFAULT)
        if name != cur:
            playing, sink = AUDIO_STATES.get(name, AUDIO_STATES[AUDIO_DEFAULT])
            log(f"audio: {name}")
            i = node_id(sink)
            if i is not None:
                subprocess.run([real("wpctl"), "set-default", str(i)], **out)
            if playing and player is None:
                gen = subprocess.Popen([sys.executable, "-I", os.path.realpath(__file__), "tone"],
                                       stdout=subprocess.PIPE, stderr=sys.stdout)
                player = (gen, subprocess.Popen(
                    [real("pw-cat"), "--playback", "--raw", "--format", "s16", "--rate", "48000", "--channels", "2",
                     "-P", '{ application.name = "Music" media.name = "Lantern Hours" media.role = "Music" '
                           'application.icon-name = "audio-x-generic" }', "-"],
                    stdin=gen.stdout, stdout=sys.stdout, stderr=sys.stdout))
                gen.stdout.close()
            elif not playing and player is not None:
                for p in reversed(player):
                    p.terminate()
                player = None
            cur = name
        time.sleep(0.5)


def audio_act(name):
    """A change the OSD shows, on the default output."""
    args = {"demo-volume-up": ["set-volume", "@DEFAULT_AUDIO_SINK@", "8%+", "--limit", "1.0"],
            "demo-volume-down": ["set-volume", "@DEFAULT_AUDIO_SINK@", "8%-"],
            "demo-mute": ["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]}[name]
    subprocess.run([real("wpctl")] + args, check=True)


# ---- the system bus: the nest's own -----------------------------------------------

# Where every D-Bus client looks for the system bus. Inside the sandbox
# /run/dbus is an empty tmpfs (the seal), so this socket is the nest's.
SYSTEM_BUS = "/run/dbus/system_bus_socket"
SYSTEM_BUS_CONF = f"""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path={SYSTEM_BUS}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
  </policy>
</busconfig>
"""


def system_bus():
    """A dbus-daemon for the demo's stand-ins (BlueZ), where the shell looks
    for the system bus. Everyone in the nest may own any name on it."""
    conf = os.path.join(STATE, "home", "runtime", "system-bus.conf")
    write(conf, SYSTEM_BUS_CONF)
    subprocess.Popen([real("dbus-daemon"), "--nofork", "--nopidfile", f"--config-file={conf}"],
                     stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stdout, start_new_session=True)
    return wait_for("the system bus", lambda: os.path.exists(SYSTEM_BUS), 5)


# ---- bluetooth: BlueZ by python-dbusmock ----------------------------------------

BT_ADAPTER = "hci0"
# (address, name, BlueZ icon, paired, battery percent or None)
BT_DEVICES = [
    ("4C:87:5D:21:9A:10", "Studio Headphones", "audio-headphones", True, 78),
    ("D0:3E:7D:44:12:5B", "Desk Keyboard", "input-keyboard", True, 64),
    ("E4:17:D8:0C:6E:21", "Travel Mouse", "input-mouse", True, 91),
    ("38:18:4C:A2:7F:03", "Kitchen Speaker", "audio-card", True, None),
    ("6A:2C:91:5E:B0:47", "Living Room TV", "video-display", False, None),
]
# control/bluetooth: which paired devices are connected, and the adapter.
BT_STATES = {
    "demo-connected": {"powered": True, "connected": {"Studio Headphones", "Desk Keyboard"}},
    "demo-all": {"powered": True, "connected": {"Studio Headphones", "Desk Keyboard", "Travel Mouse"}},
    "demo-off": {"powered": False, "connected": set()},
}
BT_DEFAULT = "demo-connected"
# A Connect the panel asks for answers after this long, so the row shows
# "connecting" for a moment as a real device does.
BT_CONNECT_DELAY = 1.8


def bluetooth():
    """BlueZ (dbusmock's bluez5 template) on the nest's system bus with the
    invented devices, kept to control/bluetooth."""
    import dbus

    mock = subprocess.Popen([sys.executable, "-m", "dbusmock", "--system", "--template", "bluez5"],
                            stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stdout)
    bus = dbus.SystemBus()
    if not wait_for("BlueZ", lambda: bus.name_has_owner("org.bluez"), 10):
        mock.terminate()
        return
    bluez = dbus.Interface(bus.get_object("org.bluez", "/"), "org.bluez.Mock")
    adapter_path = bluez.AddAdapter(BT_ADAPTER, "desk")
    adapter = dbus.Interface(bus.get_object("org.bluez", adapter_path), "org.freedesktop.DBus.Mock")
    paths = {}
    for addr, name, icon, paired, battery in BT_DEVICES:
        path = bluez.AddDevice(BT_ADAPTER, addr, name)
        paths[name] = path
        dev = dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Mock")
        dev.UpdateProperties("org.bluez.Device1", {
            "Icon": dbus.String(icon), "Paired": dbus.Boolean(paired), "Trusted": dbus.Boolean(paired),
            "Class": dbus.UInt32(0x240404 if icon.startswith("audio") else 0x2540),
        })
        # Not in the template's device: added, not updated.
        dev.AddProperties("org.bluez.Device1", {"Bonded": dbus.Boolean(paired)})
        if battery is not None:
            dev.AddProperties("org.bluez.Battery1", {"Percentage": dbus.Byte(battery)})
        # The panel's connect, answered late; its disconnect, at once.
        dev.AddMethod("org.bluez.Device1", "Connect", "", "",
                      f"import time; time.sleep({BT_CONNECT_DELAY}); "
                      "self.UpdateProperties('org.bluez.Device1', {'Connected': dbus.Boolean(True), 'ServicesResolved': dbus.Boolean(True)})")
        dev.AddMethod("org.bluez.Device1", "Disconnect", "", "",
                      "self.UpdateProperties('org.bluez.Device1', {'Connected': dbus.Boolean(False), 'ServicesResolved': dbus.Boolean(False)})")
    cur = None
    first = True
    while True:
        name = control("bluetooth", BT_DEFAULT)
        if name != cur:
            st = BT_STATES.get(name, BT_STATES[BT_DEFAULT])
            log(f"bluetooth: {name}")
            try:
                adapter.UpdateProperties("org.bluez.Adapter1", {"Powered": dbus.Boolean(st["powered"])})
                for dev_name, path in paths.items():
                    on = dev_name in st["connected"]
                    dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Mock").UpdateProperties(
                        "org.bluez.Device1", {"Connected": dbus.Boolean(on), "ServicesResolved": dbus.Boolean(on)})
            except dbus.DBusException as e:
                log(f"bluetooth: {e}")
            cur = name
            if first:
                write(bt_ready_path(), "")
                first = False
        time.sleep(0.5)


# ---- network: NetworkManager by python-dbusmock ---------------------------------

NM = "org.freedesktop.NetworkManager"
# PSK key management alone: what the template needs to make a saved
# connection. The access points then get their real RSN flags: Quickshell
# names a security only with a cipher it can match to the card's (CCMP).
PSK = 0x100
WPA2_PSK = 0x100 | 0x8 | 0x80      # PSK, CCMP pairwise and group
WPA3_TRANSITION = WPA2_PSK | 0x400  # and SAE
# (name, ssid, BSSID, MHz, strength, RSN flags)
NM_APS = [
    ("Harbour", "Harbour", "3A:61:0C:8E:21:40", 5180, 84, WPA3_TRANSITION),
    ("Harbour2", "Harbour", "3A:61:0C:8E:21:41", 2437, 71, WPA3_TRANSITION),
    ("Fernwood", "Fernwood", "9C:12:B4:70:3D:12", 5240, 58, WPA2_PSK),
    ("Attic", "Attic", "F2:8A:19:44:C0:07", 2462, 41, WPA2_PSK),
    ("Library", "Library Guest", "5E:03:7B:D2:96:33", 2412, 33, 0),
]
WIFI_STATES = {"demo-joined": True, "demo-off": False}
WIFI_DEFAULT = "demo-joined"


def network():
    """NetworkManager (dbusmock's template) with a wired link up and a
    Wi-Fi card joined to one of five invented networks; control/wifi turns
    the radio off and on."""
    import dbus

    mock = subprocess.Popen([sys.executable, "-m", "dbusmock", "--system", "--template", "networkmanager"],
                            stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stdout)
    bus = dbus.SystemBus()
    if not wait_for("NetworkManager", lambda: bus.name_has_owner(NM), 10):
        mock.terminate()
        return
    nm = dbus.Interface(bus.get_object(NM, "/org/freedesktop/NetworkManager"), "org.freedesktop.DBus.Mock")
    # What Quickshell's NetworkManager backend asks for beyond the template.
    nm.AddMethod(NM, "GetAllDevices", "", "ao", f"ret = self.Get('{NM}', 'Devices')")
    nm.AddProperties(NM, {"ConnectivityCheckAvailable": dbus.Boolean(True),
                          "ConnectivityCheckEnabled": dbus.Boolean(True)})
    activated = 100
    eth = nm.AddEthernetDevice("Ethernet1", "enp2s0", activated)
    wifi = nm.AddWiFiDevice("WiFi1", "wlan0", activated)
    aps = {}
    for name, ssid, bssid, mhz, strength, rsn in NM_APS:
        aps[name] = nm.AddAccessPoint(wifi, name, ssid, bssid, 2, mhz, 866700 if mhz > 5000 else 144400, strength,
                                      PSK if rsn else 0)
        if rsn:
            dbus.Interface(bus.get_object(NM, aps[name]), "org.freedesktop.DBus.Mock").UpdateProperties(
                f"{NM}.AccessPoint", {"RsnFlags": dbus.UInt32(rsn), "WpaFlags": dbus.UInt32(0)})
    # Device properties the template leaves out, and a scan that answers:
    # LastScan in ms of CLOCK_BOOTTIME, as NetworkManager reports it.
    for path, mac in ((eth, "8C:1F:64:2A:7E:10"), (wifi, "4E:95:0B:61:D3:2C")):
        dev = dbus.Interface(bus.get_object(NM, path), "org.freedesktop.DBus.Mock")
        dev.AddProperties(f"{NM}.Device", {"Autoconnect": dbus.Boolean(True), "HwAddress": dbus.String(mac),
                                           "InterfaceFlags": dbus.UInt32(0x10003)})
    wdev = dbus.Interface(bus.get_object(NM, wifi), "org.freedesktop.DBus.Mock")
    wdev.AddProperties(f"{NM}.Device.Wireless", {
        "LastScan": dbus.Int64(int(time.clock_gettime(time.CLOCK_BOOTTIME) * 1000)),
        "ActiveAccessPoint": dbus.ObjectPath(aps["Harbour"])})
    wdev.AddMethod(f"{NM}.Device.Wireless", "RequestScan", "a{sv}", "",
                   "import time; self.UpdateProperties('org.freedesktop.NetworkManager.Device.Wireless', "
                   "{'LastScan': dbus.Int64(int(time.clock_gettime(time.CLOCK_BOOTTIME) * 1000))})")
    wifi_conn = nm.AddWiFiConnection(wifi, "Harbour", "Harbour", "wpa-psk")
    nm.AddActiveConnection([wifi], wifi_conn, aps["Harbour"], "Harbour", 2)
    settings = dbus.Interface(bus.get_object(NM, "/org/freedesktop/NetworkManager/Settings"),
                              "org.freedesktop.NetworkManager.Settings")
    wired_conn = settings.AddConnection(dbus.Dictionary({
        "connection": dbus.Dictionary({"id": "Wired connection 1", "uuid": "1f6c2b8e-4d1a-4e8b-9a3c-7d2e5f0a6b11",
                                       "type": "802-3-ethernet"}, signature="sv"),
    }, signature="sa{sv}"))
    nm.AddActiveConnection([eth], wired_conn, "/", "Wired", 2)
    manager = dbus.Interface(bus.get_object(NM, "/org/freedesktop/NetworkManager"), "org.freedesktop.DBus.Mock")
    write(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-network.ready"), "")
    cur = None
    while True:
        name = control("wifi", WIFI_DEFAULT)
        if name != cur:
            log(f"network: {name}")
            try:
                manager.UpdateProperties(NM, {"WirelessEnabled": dbus.Boolean(WIFI_STATES.get(name, True))})
            except dbus.DBusException as e:
                log(f"network: {e}")
            cur = name
        time.sleep(0.5)


# ---- tray: one app with a menu ------------------------------------------------------

WATCHER = "org.kde.StatusNotifierWatcher"
ITEM_IFACE = "org.kde.StatusNotifierItem"
MENU_IFACE = "com.canonical.dbusmenu"
# id: (properties, children). A menu with what TrayMenu.qml draws: plain
# items, a check, a radio pair, a submenu, separators, a disabled item.
TRAY_MENU = {
    0: ({"children-display": "submenu"}, [1, 2, 3, 4, 5, 6, 10, 11, 12]),
    1: ({"label": "Pause"}, []),
    2: ({"label": "Next Track"}, []),
    3: ({"type": "separator"}, []),
    4: ({"label": "Shuffle", "toggle-type": "checkmark", "toggle-state": 1}, []),
    5: ({"label": "Repeat Album", "toggle-type": "radio", "toggle-state": 1}, []),
    6: ({"label": "Repeat Track", "toggle-type": "radio", "toggle-state": 0}, []),
    10: ({"label": "Recently Played", "children-display": "submenu"}, [20, 21, 22]),
    11: ({"type": "separator"}, []),
    12: ({"label": "Lyrics", "enabled": False}, []),
    20: ({"label": "Lantern Hours"}, []),
    21: ({"label": "Northern Rooms"}, []),
    22: ({"label": "Slow Tide"}, []),
}


def tray():
    """A music app's tray item (StatusNotifierItem with a DBusMenu) on the
    nest's session bus, registered with the shell's watcher whenever the
    watcher appears (each shell start or reload). Its menu only logs."""
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    bus_name = dbus.service.BusName(name, bus)

    def props_dict(props):
        return dbus.Dictionary({k: (dbus.Boolean(v) if isinstance(v, bool) else
                                    dbus.Int32(v) if isinstance(v, int) else dbus.String(v))
                                for k, v in props.items()}, signature="sv")

    def layout(i, depth):
        props, children = TRAY_MENU[i]
        kids = [layout(c, depth - 1) for c in children] if depth != 0 else []
        return dbus.Struct((dbus.Int32(i), props_dict(props), dbus.Array(kids, signature="v")), signature=None)

    class Item(dbus.service.Object):
        PROPS = {"Category": "ApplicationStatus", "Id": "music", "Title": "Music", "Status": "Active",
                 "IconName": "audio-x-generic", "IconThemePath": "", "AttentionIconName": "",
                 "OverlayIconName": "", "ItemIsMenu": False, "Menu": dbus.ObjectPath("/MenuBar"),
                 "ToolTip": dbus.Struct(("", dbus.Array([], signature="(iiay)"), "Music",
                                         "Lantern Hours"), signature="sa(iiay)ss")}

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.PROPS[prop] if iface == ITEM_IFACE else None

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return dbus.Dictionary(self.PROPS if iface == ITEM_IFACE else {}, signature="sv")

        @dbus.service.method(ITEM_IFACE, in_signature="ii")
        def Activate(self, x, y):
            log("tray: activate")

        @dbus.service.method(ITEM_IFACE, in_signature="ii")
        def SecondaryActivate(self, x, y):
            log("tray: secondary activate")

        @dbus.service.method(ITEM_IFACE, in_signature="is")
        def Scroll(self, delta, orientation):
            log(f"tray: scroll {delta}")

        @dbus.service.method(ITEM_IFACE, in_signature="ii")
        def ContextMenu(self, x, y):
            log("tray: context menu")

    class Menu(dbus.service.Object):
        PROPS = {"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal",
                 "IconThemePath": dbus.Array([], signature="s")}

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.PROPS[prop]

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return dbus.Dictionary(self.PROPS if iface == MENU_IFACE else {}, signature="sv")

        @dbus.service.method(MENU_IFACE, in_signature="iias", out_signature="u(ia{sv}av)")
        def GetLayout(self, parent, depth, names):
            return dbus.UInt32(1), layout(parent, depth)

        @dbus.service.method(MENU_IFACE, in_signature="aias", out_signature="a(ia{sv})")
        def GetGroupProperties(self, ids, names):
            return dbus.Array([dbus.Struct((dbus.Int32(i), props_dict(TRAY_MENU[i][0])))
                               for i in (ids or TRAY_MENU) if i in TRAY_MENU], signature="(ia{sv})")

        @dbus.service.method(MENU_IFACE, in_signature="isvu")
        def Event(self, i, event, data, timestamp):
            log(f"tray: menu {event} {TRAY_MENU.get(i, ({},))[0].get('label', i)}")

        @dbus.service.method(MENU_IFACE, in_signature="a(isvu)", out_signature="ai")
        def EventGroup(self, events):
            for i, event, data, ts in events:
                self.Event(i, event, data, ts)
            return dbus.Array([], signature="i")

        @dbus.service.method(MENU_IFACE, in_signature="i", out_signature="b")
        def AboutToShow(self, i):
            return False

        @dbus.service.method(MENU_IFACE, in_signature="ai", out_signature="aiai")
        def AboutToShowGroup(self, ids):
            return dbus.Array([], signature="i"), dbus.Array([], signature="i")

        @dbus.service.signal(MENU_IFACE, signature="ui")
        def LayoutUpdated(self, revision, parent):
            pass

    Item(bus_name, "/StatusNotifierItem")
    Menu(bus_name, "/MenuBar")

    def register(owner):
        if not owner:
            return
        try:
            bus.get_object(WATCHER, "/StatusNotifierWatcher").RegisterStatusNotifierItem(
                name, dbus_interface=WATCHER)
            log("tray: registered with the shell's watcher")
        except dbus.DBusException as e:
            log(f"tray: {e}")

    bus.watch_name_owner(WATCHER, register)
    write(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-tray.ready"), "")
    GLib.MainLoop().run()


# ---- polkit: an authority that asks once -------------------------------------------

POLKIT = "org.freedesktop.PolicyKit1"
POLKIT_AUTHORITY = f"{POLKIT}.Authority"
POLKIT_AGENT = f"{POLKIT}.AuthenticationAgent"
# What the request reads like: an ordinary system change asked for by a
# program the demo's machine has, for the administrator.
POLKIT_REQUEST = ("org.freedesktop.timedate1.set-timezone",
                  "Authentication is required to change the system time zone.",
                  "preferences-system-time", {"polkit.subject-pid": "2214", "polkit.caller-pid": "2214"})


def polkit():
    """The polkit authority on the nest's system bus: it takes the shell's
    agent registration and, when control/polkit says demo-ask, sends the
    agent one authentication request for root, then never answers it.
    Never type into the dialog: polkit's helper would try the password."""
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    name = dbus.service.BusName(POLKIT, bus)
    agents = []

    class Authority(dbus.service.Object):
        PROPS = {"BackendName": "js", "BackendVersion": "126", "BackendFeatures": dbus.UInt32(1)}

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
        def Get(self, iface, prop):
            return self.PROPS[prop]

        @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, iface):
            return dbus.Dictionary(self.PROPS, signature="sv")

        @dbus.service.method(POLKIT_AUTHORITY, in_signature="(sa{sv})ss", sender_keyword="sender")
        def RegisterAuthenticationAgent(self, subject, locale, path, sender=None):
            agents.append((sender, path))
            log(f"polkit: agent registered ({subject[0]}, {path})")

        @dbus.service.method(POLKIT_AUTHORITY, in_signature="(sa{sv})ssa{sv}", sender_keyword="sender")
        def RegisterAuthenticationAgentWithOptions(self, subject, locale, path, options, sender=None):
            self.RegisterAuthenticationAgent(subject, locale, path, sender=sender)

        @dbus.service.method(POLKIT_AUTHORITY, in_signature="(sa{sv})s", sender_keyword="sender")
        def UnregisterAuthenticationAgent(self, subject, path, sender=None):
            agents[:] = [a for a in agents if a != (sender, path)]

        @dbus.service.method(POLKIT_AUTHORITY, in_signature="us(sa{sv})", out_signature="")
        def AuthenticationAgentResponse2(self, uid, cookie, identity):
            log("polkit: the agent answered (not acted on)")

        @dbus.service.method(POLKIT_AUTHORITY, in_signature="s(sa{sv})", out_signature="")
        def AuthenticationAgentResponse(self, cookie, identity):
            log("polkit: the agent answered (not acted on)")

    Authority(name, "/org/freedesktop/PolicyKit1/Authority")
    write(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-polkit.ready"), "")
    state = {"cur": None, "n": 0}

    def ask():
        if not agents:
            log("polkit: no agent registered to ask")
            return
        sender, path = agents[-1]
        action, message, icon, details = POLKIT_REQUEST
        state["n"] += 1
        root = dbus.Struct(("unix-user", dbus.Dictionary({"uid": dbus.UInt32(0)}, signature="sv")))
        bus.get_object(sender, path).BeginAuthentication(
            action, message, icon, dbus.Dictionary(details, signature="ss"), f"nest-demo-{state['n']}",
            dbus.Array([root], signature="(sa{sv})"), dbus_interface=POLKIT_AGENT,
            reply_handler=lambda: log("polkit: request ended"),
            error_handler=lambda e: log(f"polkit: request ended: {e.get_dbus_name()}"), timeout=3600)
        log("polkit: asked the agent")

    def poll():
        cur = control("polkit", "demo-idle")
        if cur != state["cur"]:
            state["cur"] = cur
            if cur == "demo-ask":
                ask()
        return True

    GLib.timeout_add(500, poll)
    GLib.MainLoop().run()


# ---- actions -----------------------------------------------------------------

ACTIONS = {"audio": audio_act}


def act(panel, name):
    """`desk-nest fixture <panel> <name>` for an inside fixture of a stand-in."""
    if panel not in ACTIONS:
        print(f"nest-services: no actions for {panel}", file=sys.stderr)
        sys.exit(2)
    try:
        ACTIONS[panel](name)
    except KeyError:
        print(f"nest-services: no action {panel} {name}", file=sys.stderr)
        sys.exit(2)


# ---- clock: the demo's wall clock ----------------------------------------------

def clock_path():
    return os.path.join(STATE, "home", "runtime", "demo-clock")


def clock_text(base, elapsed):
    t = base + elapsed * CLOCK_RATE
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d\n" % int((t % 1) * 1000)


def clock():
    """Writes the time libfaketime gives the shell (FAKETIME_TIMESTAMP_FILE,
    re-read once per real second) five times a second: from NEST_DEMO at a
    hundredth of real speed. A file, not FAKETIME's own x speed modifier:
    that also stretches every poll and sleep timeout by the same factor,
    and the shell's timers fire a hundred times late."""
    base = time.mktime(time.strptime(os.environ["NEST_DEMO"], "%Y-%m-%d %H:%M:%S"))
    t0 = time.monotonic()
    path = clock_path()
    while True:
        write(path, clock_text(base, time.monotonic() - t0))
        time.sleep(0.2)


# ---- start ------------------------------------------------------------------

def spawn(*args):
    """A stand-in in the background, its output in services.out, in its own
    session so the shell's restarts leave it alone."""
    return subprocess.Popen([sys.executable, "-I", os.path.realpath(__file__)] + list(args),
                            stdin=subprocess.DEVNULL, stdout=sys.stdout, stderr=sys.stdout,
                            start_new_session=True)


def bt_ready_path():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-bluetooth.ready")


def login_session():
    """The user's graphical session as logind would publish it, in the
    sandbox's own /run/systemd (an empty tmpfs, the seal). polkit's agent
    needs a session for its pid: the nest's processes sit in the user
    manager's cgroup, not a session's, so libpolkit falls back to
    sd_uid_get_display, which reads only this file. The id goes to the
    demo's own authority and nowhere else."""
    write(f"/run/systemd/users/{os.getuid()}", "# desk-nest --demo (nest/services)\nDISPLAY=demo\n")


def start():
    spawn("clock")
    login_session()
    spawn("system")
    # The shell asks BlueZ for its objects once, when it starts: the bus and
    # the devices come first.
    if system_bus():
        spawn("bluetooth")
        spawn("network")
        spawn("polkit")
    spawn("audio")
    spawn("tray")
    wait_for("BlueZ's devices", lambda: os.path.exists(bt_ready_path()), 15)
    wait_for("the polkit authority", lambda: os.path.exists(
        os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-polkit.ready")), 15)
    wait_for("NetworkManager's devices", lambda: os.path.exists(
        os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nest-network.ready")), 15)
    # The shell's Pipewire singleton binds the default output when it
    # appears; waiting for it gives the bar and the OSD a settled graph.
    wait_for("the default output", lambda: any(
        o.get("type") == "PipeWire:Interface:Metadata" and any(
            m.get("key") == "default.audio.sink" for m in o.get("metadata") or [])
        for o in pw_nodes()), 15)
    log("started: clock, system, system bus, bluetooth, network, polkit, audio, tray")


COMMANDS = {
    "sys-seed": sys_seed,
    "sys-binds": sys_binds,
    "system": system,
    "clock": clock,
    "audio": audio,
    "bluetooth": bluetooth,
    "network": network,
    "tray": tray,
    "polkit": polkit,
    "tone": tone,
    "act": act,
    "start": start,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(f"usage: nest-services {'|'.join(COMMANDS)}", file=sys.stderr)
        sys.exit(2)
    COMMANDS[sys.argv[1]](*sys.argv[2:])
