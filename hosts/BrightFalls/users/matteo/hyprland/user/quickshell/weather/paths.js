// Geometry for the weather drawings: SVG path strings for PathSvg, the
// condition art's layers, a seeded random source, and Web Mercator. Pure: no
// QML or Qt API, so node can run it.

// A circle as two clockwise half arcs.
function circle(cx, cy, r) {
    return `M${cx - r} ${cy} A${r} ${r} 0 1 1 ${cx + r} ${cy} A${r} ${r} 0 1 1 ${cx - r} ${cy} Z`;
}

// The cloud, M18 46 A9 9 0 0 1 17 28 A13 13 0 0 1 42 24 A11 11 0 0 1 46 46 Z
// in a 64 unit box, moved by (dx, dy) and scaled by s. The first and last arcs'
// radii are too small for their chords, so SVG scales them up to half the
// chord; they are written here at that size so the shape does not depend on
// the parser doing the same.
const CLOUD_TOP = 15.91;
const CLOUD_BOTTOM = 46;
function cloud(dx, dy, s) {
    const X = x => dx + x * s, Y = y => dy + y * s;
    const r1 = 9.0139 * s, r2 = 13 * s, r3 = 11.1804 * s;
    return `M${X(18)} ${Y(46)} A${r1} ${r1} 0 0 1 ${X(17)} ${Y(28)} A${r2} ${r2} 0 0 1 ${X(42)} ${Y(24)} A${r3} ${r3} 0 0 1 ${X(46)} ${Y(46)} Z`;
}

// The crescent moon of radius r about (cx, cy).
function crescent(cx, cy, r) {
    const sx = cx + .2 * r, sy = cy - .98 * r, ex = cx + .98 * r, ey = cy + .2 * r;
    return `M${sx} ${sy} A${r} ${r} 0 1 0 ${ex} ${ey} A${.8 * r} ${.8 * r} 0 0 1 ${sx} ${sy} Z`;
}

function sunRays(cx, cy, r) {
    let s = "";
    for (let i = 0; i < 8; i++) {
        const a = i * Math.PI / 4, c = Math.cos(a), n = Math.sin(a);
        s += `M${cx + c * (r + 4)} ${cy + n * (r + 4)} L${cx + c * (r + 8.5)} ${cy + n * (r + 8.5)} `;
    }
    return s;
}

function cloudLayer(dx, dy, s, tone) {
    return {
        path: cloud(dx, dy, s),
        y1: dy + CLOUD_TOP * s,
        y2: dy + CLOUD_BOTTOM * s,
        tone: tone
    };
}

const NO_CLOUD = {
    path: "",
    y1: 0,
    y2: 1,
    tone: "light"
};

// The layers of one condition kind in a 64 unit box, back to front: sun,
// moon, stars, two clouds, bolt, drops, flakes, fog bars, wind. The sun and
// moon are [cx, cy, r] or null; other absent layers are empty paths. An
// unknown kind draws nothing.
function art(kind) {
    const a = {
        rays: "",
        sun: null,
        moon: null,
        stars: "",
        clouds: [NO_CLOUD, NO_CLOUD],
        bolt: "",
        drops: "",
        flakes: "",
        bars: "",
        wind: ""
    };
    const sun = (cx, cy, r) => {
        a.rays = sunRays(cx, cy, r);
        a.sun = [cx, cy, r];
    };
    const moon = (cx, cy, r) => a.moon = [cx, cy, r];
    const stars = list => a.stars = list.map(([x, y, r]) => circle(x, y, r)).join(" ");
    const drops = list => a.drops = list.map(([x, y, l]) => `M${x} ${y} L${x - l * .38} ${y + l}`).join(" ");
    const flakes = list => a.flakes = list.map(([x, y]) => circle(x, y, 2.3)).join(" ");
    switch (kind) {
    case "sunny":
        sun(32, 32, 12);
        break;
    case "clear-night":
        moon(29, 33, 16);
        stars([[48, 16, 1.8], [54, 30, 1.3], [40, 9, 1.2]]);
        break;
    case "partlycloudy":
        sun(23, 22, 9);
        a.clouds = [cloudLayer(8, 12, .9, "light"), NO_CLOUD];
        break;
    case "partlycloudy-night":
        moon(20, 22, 11);
        stars([[46, 12, 1.4]]);
        a.clouds = [cloudLayer(8, 12, .9, "dark"), NO_CLOUD];
        break;
    case "cloudy":
        a.clouds = [cloudLayer(18, 2, .72, "dark"), cloudLayer(0, 8, 1, "light")];
        break;
    case "rainy":
        a.clouds = [cloudLayer(0, -1, 1, "dark"), NO_CLOUD];
        drops([[23, 50, 8], [33, 50, 8], [43, 50, 8]]);
        break;
    case "pouring":
        a.clouds = [cloudLayer(0, -3, 1, "black"), NO_CLOUD];
        drops([[18, 48, 12], [26, 48, 12], [34, 48, 12], [42, 48, 12], [50, 48, 12]]);
        break;
    case "lightning-rainy":
        a.clouds = [cloudLayer(0, -3, 1, "black"), NO_CLOUD];
        a.bolt = "M35 40 L26 53 H32 L29 63 L41 49 H34 L38 40 Z";
        drops([[19, 48, 9], [49, 48, 9]]);
        break;
    case "snowy":
        a.clouds = [cloudLayer(0, -2, 1, "light"), NO_CLOUD];
        flakes([[22, 52], [32, 57], [42, 52], [27, 62], [38, 62]]);
        break;
    case "snowy-rainy":
        a.clouds = [cloudLayer(0, -2, 1, "dark"), NO_CLOUD];
        drops([[22, 49, 8], [44, 49, 8]]);
        flakes([[32, 53], [27, 61], [39, 61]]);
        break;
    case "fog":
        a.clouds = [cloudLayer(4, -6, .88, "dark"), NO_CLOUD];
        a.bars = [[10, 50, 46], [16, 54, 53], [12, 44, 60]].map(([x1, x2, y]) => `M${x1} ${y} L${x2} ${y}`).join(" ");
        break;
    case "windy":
        a.wind = "M8 25 H36 a6.5 6.5 0 1 0 -6.5 -6.5 M8 36 H47 a7 7 0 1 1 -7 7 M8 47 H27";
        break;
    }
    return a;
}

// A random source in [0, 1) from a 32-bit seed (mulberry32), the same
// sequence as the design page's, so a seed places things as it drew them.
function rng(seed) {
    let s = seed | 0;
    return () => {
        s = s + 0x6D2B79F5 | 0;
        let t = Math.imul(s ^ s >>> 15, 1 | s);
        t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
}

// Web Mercator world pixels at 256 px tiles.
function project(lon, lat, zoom) {
    const n = 256 * Math.pow(2, zoom), phi = lat * Math.PI / 180;
    return [(lon + 180) / 360 * n, (1 - Math.log(Math.tan(phi) + 1 / Math.cos(phi)) / Math.PI) / 2 * n];
}

// The latitude at world pixel row y.
function latitude(y, zoom) {
    const n = 256 * Math.pow(2, zoom);
    return Math.atan(Math.sinh(Math.PI * (1 - 2 * y / n))) * 180 / Math.PI;
}

// Ground metres per pixel at a latitude, for 256 px tiles.
function metresPerPixel(lat, zoom) {
    return 156543.03 * Math.cos(lat * Math.PI / 180) / Math.pow(2, zoom);
}
// The sky scene's moving and scattered things for a w × h scene, from
// `seed` (0 counts as 11): stars at night, clouds by cover, fog bands, rain
// lines (rain × 22 of them) and snow flakes. The random numbers are drawn in
// the design page's order, so a seed gives the picture it drew. `delay` is
// seconds into the thing's own loop. A blank scene has none.
function sceneLayout(o) {
    const r = rng(o.seed || 11), w = o.w, h = o.h, hz = h - 26, oc = o.cloud || 0;
    const out = {
        stars: [],
        clouds: [],
        fog: [],
        rain: [],
        snow: []
    };
    if (o.blank)
        return out;
    if (!o.day)
        for (let i = 0; i < 46; i++) {
            const x = r() * w, y = r() * hz * .9, q = .5 + r() * .9;
            out.stars.push({
                x: x,
                y: y,
                r: q,
                opacity: (.35 + r() * .5) * (1 - oc * .9),
                twinkle: i % 5 === 0
            });
        }
    const n = oc ? Math.round(oc * 7) + 1 : 0;
    for (let i = 0; i < n; i++) {
        const x = (i + r() * .8) / n * (w + 40) - 50, y = -14 + r() * (h * .34), k = .9 + r() * 1.1;
        out.clouds.push({
            x: x,
            y: y,
            scale: k,
            opacity: .55 + r() * .35
        });
    }
    if (o.fog)
        for (let i = 0; i < 5; i++)
            out.fog.push({
                x: -20 + r() * 40,
                y: hz - 60 + i * 15,
                opacity: .1 + i * .035
            });
    if (o.rain)
        for (let i = 0; i < o.rain * 22; i++) {
            const x = r() * (w + 40);
            out.rain.push({
                path: `M${x} -10 L${x - (hz + 10) * .2} ${hz + 2}`,
                delay: r()
            });
        }
    if (o.snow)
        for (let i = 0; i < 60; i++) {
            const x = r() * w, y = r() * hz, q = .9 + r() * 1.1, op = .5 + r() * .5;
            out.snow.push({
                x: x,
                y: y,
                r: q,
                opacity: op,
                delay: r() * 3
            });
        }
    return out;
}

// sceneLayout()'s rain lines in `n` groups by their delay, each group one
// path and one delay (the start of its slice of the 0.65 s loop), so a few
// shapes move instead of one per line. Empty groups are left out.
function rainGroups(rain, n) {
    const groups = [];
    for (let k = 0; k < n; k++) {
        const lines = rain.filter(l => Math.min(n - 1, Math.floor(l.delay * n)) === k);
        if (lines.length)
            groups.push({
                path: lines.map(l => l.path).join(" "),
                delay: k / n,
                count: lines.length
            });
    }
    return groups;
}

// The sun's or moon's dotted arc, and the point at `frac` along it.
function skyArc(w, h) {
    const pts = [];
    for (let i = 0; i <= 40; i++)
        pts.push(skyPoint(w, h, i / 40).join(" "));
    return "M" + pts.join(" L");
}

function skyPoint(w, h, q) {
    const pad = 40, hz = h - 26;
    return [pad + q * (w - 2 * pad), hz + 4 - Math.sin(Math.PI * q) * (h - 62)];
}

// Ground, three houses with chimneys and three trees, one path for a
// nonzero fill (every part runs clockwise), and the houses' windows.
function skyline(w, h) {
    const hz = h - 26;
    let s = `M0 ${h} V${hz + 5} Q${w * .16} ${hz - 6} ${w * .34} ${hz + 3} T${w * .66} ${hz + 1} T${w} ${hz + 4} V${h} Z`;
    const windows = [];
    const house = (x, wd, ht) => {
        s += ` M${x} ${hz + 6} V${hz - ht} L${x + wd / 2} ${hz - ht - wd * .42} L${x + wd} ${hz - ht} V${hz + 6} Z`;
        s += ` M${x + wd * .68} ${hz - ht - wd * .2} v${-wd * .3} h${wd * .14} v${wd * .42} Z`;
        windows.push({
            x: x + wd * .22,
            y: hz - ht + 4,
            w: wd * .2,
            h: wd * .22
        });
    };
    const tree = (x, q) => {
        s += ` M${x - 1} ${hz - 6 * q} h2 v${8 * q + 4} h-2 Z`;
        s += " " + circle(x, hz - 10 * q, 6 * q) + " " + circle(x + 4 * q, hz - 6 * q, 4.5 * q);
    };
    house(w * .56, 26, 13);
    house(w * .56 + 30, 22, 17);
    house(w * .56 + 58, 30, 12);
    tree(w * .13, 1.2);
    tree(w * .92, 1);
    tree(w * .47, .8);
    return {
        path: s,
        windows: windows
    };
}

// 0 → 1 → 0 over 2 × period seconds, eased in and out: a CSS animation
// with `alternate` and ease-in-out, as the design page's.
function swing(t, period) {
    const q = (t / period) % 2;
    return .5 - .5 * Math.cos(Math.PI * (q > 1 ? 2 - q : q));
}

if (typeof module !== "undefined")
    module.exports = { circle, cloud, crescent, sunRays, art, rng, project, latitude, metresPerPixel, sceneLayout, rainGroups, skyArc, skyPoint, skyline, swing };
