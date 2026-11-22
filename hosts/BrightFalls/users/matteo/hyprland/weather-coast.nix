# The weather panel's British Isles outline: one JSON file, an array of
# closed rings, each an array of [lon, lat] (3 decimals). Natural Earth's 50m
# land polygons (public domain), clipped to a box that covers the radar's
# fixed tile block (zoom 6, x 30-32, y 18-21: about -11.25..5.63 E,
# 48.92..61.61 N) and simplified to 1 px at zoom 6 in Web Mercator.
{
  fetchurl,
  python3,
  runCommand,
}:
let
  land = fetchurl {
    url = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_50m_land.geojson";
    hash = "sha256-6HSyelHRRkUr42DK+zzFDIYAEHSmfVNBE+ZTRoL5gms=";
  };
  script = builtins.toFile "weather-coast.py" ''
    import json
    import math
    import sys

    W, E, S, N = -11.5, 6.0, 48.5, 62.0
    ZOOM = 6
    TOLERANCE = 1.0  # pixels at ZOOM, 256 px tiles


    def project(p):
        n = 256 * 2 ** ZOOM
        lat = math.radians(p[1])
        return ((p[0] + 180) / 360 * n,
                (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)


    def clip(ring):
        # Sutherland-Hodgman against each side of the box in turn.
        sides = [(0, W, 1), (0, E, -1), (1, S, 1), (1, N, -1)]
        for axis, edge, sign in sides:
            if not ring:
                return []
            out = []
            for i, cur in enumerate(ring):
                prev = ring[i - 1]
                cin = (cur[axis] - edge) * sign >= 0
                pin = (prev[axis] - edge) * sign >= 0
                if cin != pin:
                    t = (edge - prev[axis]) / (cur[axis] - prev[axis])
                    out.append([prev[0] + t * (cur[0] - prev[0]),
                                prev[1] + t * (cur[1] - prev[1])])
                if cin:
                    out.append(cur)
            ring = out
        return ring


    def simplify(pts, px):
        # Douglas-Peucker over the projected points; returns kept indices.
        keep = {0, len(pts) - 1}
        stack = [(0, len(pts) - 1)]
        while stack:
            a, b = stack.pop()
            ax, ay = px[a]
            bx, by = px[b]
            dx, dy = bx - ax, by - ay
            seg = math.hypot(dx, dy)
            best, at = 0.0, -1
            for i in range(a + 1, b):
                x, y = px[i]
                if seg == 0:
                    d = math.hypot(x - ax, y - ay)
                else:
                    d = abs(dy * (x - ax) - dx * (y - ay)) / seg
                if d > best:
                    best, at = d, i
            if best > TOLERANCE:
                keep.add(at)
                stack += [(a, at), (at, b)]
        return sorted(keep)


    def area(px):
        return abs(sum(px[i - 1][0] * p[1] - p[0] * px[i - 1][1]
                       for i, p in enumerate(px))) / 2


    rings = []
    for f in json.load(open(sys.argv[1]))["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            for ring in poly:
                r = clip([p[:2] for p in ring[:-1]])
                if len(r) < 3:
                    continue
                r.append(r[0])
                px = [project(p) for p in r]
                kept = simplify(r, px)
                if len(kept) < 4 or area([px[i] for i in kept]) < 2:
                    continue
                rings.append([[round(r[i][0], 3), round(r[i][1], 3)] for i in kept])

    with open(sys.argv[2], "w") as out:
        json.dump(rings, out, separators=(",", ":"))
    print(len(rings), "rings,", sum(len(r) for r in rings), "points", file=sys.stderr)
  '';
in
runCommand "weather-coast.json" { nativeBuildInputs = [ python3 ]; } ''
  python3 ${script} ${land} $out
''
