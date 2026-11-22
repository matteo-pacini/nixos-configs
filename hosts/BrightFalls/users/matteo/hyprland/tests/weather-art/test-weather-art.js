// The weather drawings' geometry (quickshell/weather/paths.js): the Web
// Mercator projection the radar map places the coast and the ring with, and
// the sky scene's layout, which must be the same for the same inputs.
// Run: node test-weather-art.js <path to paths.js>
const assert = require("node:assert/strict");
const path = require("node:path");

const P = require(path.resolve(process.argv[2]));
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

t("projection: the origin, Greenwich in the radar block, the inverse", () => {
    const [x, y] = P.project(0, 0, 6);
    assert.ok(Math.abs(x - 8192) < 1e-9 && Math.abs(y - 8192) < 1e-9);
    assert.ok(Math.abs(P.project(180, 0, 0)[0] - 256) < 1e-9);
    const [gx, gy] = P.project(-0.0005, 51.4769, 6);
    assert.equal(Math.floor(gx / 256), 31);
    assert.equal(Math.floor(gy / 256), 21);
    // The block's corners: x 30..32, y 18..21 at zoom 6 (the contract's).
    const [wx, ny] = P.project(-11.25, 61.6, 6);
    assert.equal(Math.floor(wx / 256), 30);
    assert.equal(Math.floor(ny / 256), 18);
    for (const lat of [49, 51.48, 55.6, 61])
        assert.ok(Math.abs(P.latitude(P.project(0, lat, 6)[1], 6) - lat) < 1e-9, `latitude(${lat})`);
    // 100 km at 52° N, zoom 6: about 1506 m a pixel, so about 66 px.
    assert.ok(Math.abs(100000 / P.metresPerPixel(52, 6) - 66.4) < 0.1);
});

t("scene layout: the same inputs give the same picture; counts as drawn", () => {
    const o = { blank: false, day: false, cloud: 0.85, rain: 1, snow: true, fog: true, seed: 14, w: 418, h: 170 };
    const a = P.sceneLayout(o), b = P.sceneLayout(Object.assign({}, o));
    assert.equal(JSON.stringify(a), JSON.stringify(b));
    assert.equal(a.stars.length, 46);
    assert.equal(a.clouds.length, Math.round(0.85 * 7) + 1);
    assert.equal(a.fog.length, 5);
    assert.equal(a.rain.length, 22);
    assert.equal(a.snow.length, 60);
    assert.notEqual(JSON.stringify(P.sceneLayout(Object.assign({}, o, { seed: 15 }))), JSON.stringify(a));
    // Seed 0 counts as 11, as on the design page.
    assert.equal(JSON.stringify(P.sceneLayout(Object.assign({}, o, { seed: 0 }))), JSON.stringify(P.sceneLayout(Object.assign({}, o, { seed: 11 }))));
    // No stars by day; nothing at all when blank.
    assert.equal(P.sceneLayout(Object.assign({}, o, { day: true })).stars.length, 0);
    const blank = P.sceneLayout(Object.assign({}, o, { blank: true }));
    assert.equal(blank.stars.length + blank.clouds.length + blank.fog.length + blank.rain.length + blank.snow.length, 0);
});

console.log(`ok: ${n} tests`);
