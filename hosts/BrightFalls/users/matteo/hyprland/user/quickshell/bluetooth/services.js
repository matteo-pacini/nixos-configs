// What a device asks for when BlueZ's agent gets AuthorizeService: the
// service's name in plain words and the question the modal puts. Plain
// JavaScript so node can run it too (tests beside the panel's report).
//
// The UUID is the service on this computer that the device wants to use, so
// "Audio Sink" means this computer would play the device's audio. Names of
// the 16-bit UUIDs follow BlueZ 5.87's table (src/shared/util.c).

// 16-bit UUID -> [name, question]; {d} is the device's name.
const SERVICES = {
    "110a": ["Audio streaming (A2DP source)", "Let {d} receive audio from this computer?"],
    "110b": ["Audio streaming (A2DP sink)", "Let {d} play its audio through this computer?"],
    "110d": ["Audio streaming (A2DP)", "Let {d} stream audio with this computer?"],
    "1108": ["Headset calls (HSP)", "Let {d} take its calls through this computer's microphone and speakers?"],
    "1131": ["Headset calls (HSP)", "Let {d} take its calls through this computer's microphone and speakers?"],
    "1112": ["Headset calls (HSP gateway)", "Let {d} work as a headset for calls on this computer?"],
    "111e": ["Hands-free calls (HFP)", "Let {d} take its calls through this computer's microphone and speakers?"],
    "111f": ["Hands-free calls (HFP gateway)", "Let {d} work as a hands-free set for calls on this computer?"],
    "110c": ["Media controls (AVRCP)", "Let {d} play, pause, skip and change the volume of what plays here?"],
    "110e": ["Media controls (AVRCP)", "Let {d} be controlled from this computer: play, pause, skip, volume?"],
    "110f": ["Media controls (AVRCP)", "Let {d} be controlled from this computer: play, pause, skip, volume?"],
    "1124": ["Keyboard or mouse input (HID)", "Let {d} type, click or play on this computer as a keyboard, mouse or controller?"],
    "1812": ["Keyboard or mouse input (HOGP)", "Let {d} type, click or play on this computer as a keyboard, mouse or controller?"],
    "1116": ["Network sharing (PAN, NAP)", "Let {d} use this computer's network connection?"],
    "1115": ["Network sharing (PAN, PANU)", "Let {d} share its network connection with this computer?"],
    "1117": ["Network sharing (PAN, GN)", "Let {d} join a small network with this computer?"],
    "1105": ["File transfer (OBEX push)", "Let {d} send files to this computer?"],
    "1106": ["File transfer (OBEX FTP)", "Let {d} browse and copy files on this computer?"],
    "112f": ["Contacts (PBAP)", "Let {d} read the contacts on this computer?"],
    "112e": ["Contacts (PBAP)", "Let {d} share its contacts with this computer?"],
    "1130": ["Contacts (PBAP)", "Let {d} exchange contacts with this computer?"],
    "1132": ["Messages (MAP)", "Let {d} read and send messages through this computer?"],
    "1133": ["Messages (MAP)", "Let {d} tell this computer about new messages?"],
    "1134": ["Messages (MAP)", "Let {d} exchange messages with this computer?"],
    "112d": ["SIM access (SAP)", "Let {d} use a SIM card through this computer?"],
    "1101": ["Serial port (SPP)", "Let {d} open a serial connection to this computer?"],
    "184e": ["LE Audio streaming", "Let {d} stream audio with this computer over LE Audio?"],
    "1850": ["LE Audio capabilities", "Let {d} read which audio formats this computer supports?"],
    "1855": ["Calls and media audio (LE Audio)", "Let {d} use this computer for calls and media over LE Audio?"],
    "1858": ["Gaming audio (LE Audio)", "Let {d} use this computer for game audio over LE Audio?"],
    "1853": ["Common audio (LE Audio)", "Let {d} use this computer's LE Audio services?"],
    "1844": ["Volume control (LE Audio)", "Let {d} change this computer's volume?"],
    "1845": ["Volume control (LE Audio)", "Let {d} change this computer's volume?"],
    "1843": ["Audio input control (LE Audio)", "Let {d} control this computer's audio inputs?"],
    "184d": ["Microphone control (LE Audio)", "Let {d} mute and unmute this computer's microphone?"],
    "1848": ["Media controls (LE Audio)", "Let {d} play, pause and skip what plays here?"],
    "1849": ["Media controls (LE Audio)", "Let {d} play, pause and skip what plays here?"],
    "184b": ["Calls (LE Audio)", "Let {d} answer and end calls on this computer?"],
    "184c": ["Calls (LE Audio)", "Let {d} answer and end calls on this computer?"],
    "184f": ["Broadcast audio (LE Audio)", "Let {d} tune this computer to an audio broadcast?"],
    "1846": ["Earbud set (LE Audio)", "Let {d} pair up its set of earbuds with this computer?"],
    "1854": ["Hearing aid (LE Audio)", "Let {d} work as a hearing aid with this computer?"]
};

const BASE = /^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$/;

// "110d" for a Bluetooth base UUID, else the first block of the UUID.
function shortUuid(uuid) {
    const u = String(uuid).toLowerCase();
    const m = u.match(BASE);
    return m ? m[1] : u.split("-")[0];
}

// { name, question, known, short } for `uuid` asked for by `device`.
function describe(uuid, device) {
    const short = shortUuid(uuid);
    const entry = SERVICES[short];
    const d = device || "This device";
    if (entry)
        return { name: entry[0], question: entry[1].replace("{d}", d), known: true, short };
    return { name: "an unlisted service", question: `Let ${d} use an unlisted service on this computer?`, known: false, short };
}

const CALLS = ["111e", "111f", "1108", "1112", "1131"];

// What a device does through this computer, from evidence only:
//   links    the agent's "links" event for it (BlueZ media transports,
//            AVRCP and PAN connected, and `calls`: "none", "connected" or
//            "active" from PipeWire's hands-free link), or null
//   nodes    its PipeWire nodes as [{ profile: api.bluez5.profile,
//            mediaClass, linked }], linked meaning an active link to or
//            from another node; calls (HFP/HSP) have nodes only while a
//            call's audio is open, since PipeWire, not BlueZ, runs that
//            profile
//   answers  { uuid: true | false } for the AuthorizeService questions the
//            user answered for it
// Returns { roles, lines }: roles as [{ id, state }] for the row's glyphs,
// state "active" (in use now), "connected" or "allowed" (may be used, not
// now); lines as [[what, state]] for details.
function uses(links, nodes, answers, device) {
    const d = device || "the device";
    const roles = [];
    const lines = [];
    const covered = new Set();

    // An agent older than the `calls` field leaves it undefined: then
    // nothing is known about the link, only about the answer.
    const calls = links?.calls;
    const callNode = nodes.some(n => String(n.profile).startsWith("headset-"));
    const callAnswer = Object.keys(answers).find(u => CALLS.includes(shortUuid(u)));
    for (const u of Object.keys(answers))
        if (CALLS.includes(shortUuid(u)))
            covered.add(u);
    if (callNode || calls === "active") {
        roles.push({ id: "calls", state: "active" });
        lines.push(["calls through this computer", "in a call now"]);
    } else if (calls === "connected") {
        roles.push({ id: "calls", state: "connected" });
        lines.push(["calls through this computer", "connected, no call now"]);
    } else if (callAnswer !== undefined) {
        if (answers[callAnswer])
            roles.push({ id: "calls", state: "allowed" });
        const allowed = calls === undefined ? "allowed, no call now" : "allowed, not connected";
        lines.push(["calls through this computer", answers[callAnswer] ? allowed : "denied"]);
    }

    // Played here only when PipeWire has the device's audio node linked;
    // BlueZ alone says nothing about where the audio goes.
    const audioNodes = nodes.filter(n => /^(a2dp|bap)-/.test(String(n.profile)));
    const playing = audioNodes.some(n => n.linked);
    const transports = links?.transports ?? [];
    for (const t of transports) {
        const short = shortUuid(t.uuid);
        const what = short === "110b" ? `audio from ${d}` : short === "110a" ? `audio from here to ${d}` : "audio (LE Audio)";
        let state = "connected, idle";
        if (playing)
            state = short === "110a" ? "playing on it now" : "playing here now";
        else if (t.state === "active")
            state = short === "110a" ? "sending, nothing linked to it" : "sending, not reaching the speakers";
        lines.push([what, state]);
    }
    if (transports.length === 0 && audioNodes.length > 0)
        lines.push(["audio", playing ? "playing now" : "connected"]);
    if (transports.length > 0 || audioNodes.length > 0)
        roles.push({ id: "audio", state: playing ? "active" : "connected" });

    if (links?.control) {
        roles.push({ id: "controls", state: "connected" });
        lines.push(["media controls (AVRCP)", "connected"]);
    }
    if (links?.network) {
        roles.push({ id: "network", state: "active" });
        lines.push(["network sharing (PAN)", "in use now"]);
    }

    for (const u of Object.keys(answers)) {
        if (covered.has(u))
            continue;
        const s = describe(u, device);
        lines.push([s.known ? s.name : `${s.name} (${s.short})`, answers[u] ? "allowed" : "denied"]);
    }
    return { roles, lines };
}

if (typeof module !== "undefined")
    module.exports = { SERVICES, shortUuid, describe, uses };
