// Renders the office sprites: one SVG per pose (poses.json, pixel maps) and
// app (palettes.json, keyed by the app herdr reports; "agent" for any other),
// named `<pose>-<app>.svg`, into the folder given as the only argument.
// GPUI draws full-colour images as they are and can't recolour them, hence a
// file per app.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const here = new URL(".", import.meta.url);
const poses = JSON.parse(readFileSync(new URL("poses.json", here), "utf8"));
const palettes = JSON.parse(readFileSync(new URL("palettes.json", here), "utf8"));
const out = process.argv[2];
// Each pixel-map cell is drawn this many px wide.
const SCALE = 3;

// Lightens towards white (amount > 0) or darkens towards black (amount < 0).
function shade(hex, amount) {
  return "#" + hex.slice(1).match(/../g).map((channel) => {
    const v = parseInt(channel, 16);
    return Math.round(amount < 0 ? v * (1 + amount) : v + (255 - v) * amount).toString(16).padStart(2, "0");
  }).join("");
}

mkdirSync(out, { recursive: true });
for (const [app, { shirt, hair }] of Object.entries(palettes)) {
  const col = {
    H: hair, h: shade(hair, 0.28), J: shade(hair, -0.3),
    B: shirt, b: shade(shirt, 0.3), D: shade(shirt, -0.28),
    S: "#edbd94", s: "#c78b70", W: "#ffe3b8", R: "#dc9680",
    K: "#20202b", P: "#343b50", p: "#4d5870", L: "#87919b",
  };
  for (const [pose, rows] of Object.entries(poses)) {
    const w = rows[0].length, h = rows.length;
    let rects = "";
    rows.forEach((row, y) => [...row].forEach((ch, x) => {
      if (col[ch]) rects += `<rect x="${x}" y="${y}" width="1" height="1" fill="${col[ch]}"/>`;
    }));
    writeFileSync(`${out}/${pose}-${app}.svg`,
      `<svg xmlns="http://www.w3.org/2000/svg" width="${w * SCALE}" height="${h * SCALE}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges">${rects}</svg>\n`);
  }
}
