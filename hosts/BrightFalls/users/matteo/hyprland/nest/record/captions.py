"""Renders a caption track to PNGs and writes the ffmpeg arguments that
overlay them. Called by caption.sh; see there for the file format.

usage: captions.py <captions.txt> <workdir> <width> <height> <fps>
Writes <workdir>/c*.png, <workdir>/inputs (ffmpeg input arguments, one per
line) and <workdir>/filter (the -filter_complex graph, output [out]).
"""
import os
import shlex
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# The shell's palette (user/quickshell/Theme.qml, builtin).
BG = (40, 42, 54)          # background #282a36
LINE = (68, 71, 90)        # current_line #44475a
FG = (248, 248, 242)       # foreground #f8f8f2
SOFT = (98, 114, 164)      # comment #6272a4
PURPLE = (189, 147, 249)   # purple #bd93f9

FADE = 0.35


def font(style, size):
    path = os.environ.get(f"CAPTION_FONT_{style.upper()}")
    return ImageFont.truetype(path, size)


def parse(path):
    pre = post = 0.0
    items = []
    with open(path) as f:
        for n, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                if not line.startswith(("pad", "title", "end")):
                    # <start> <end> [pos] <text>: the text as written, so an
                    # apostrophe or a quote in it is just text.
                    start, end, rest = line.split(None, 2)
                    pos, _, text = rest.partition(" ")
                    if pos not in ("bottom", "top", "center") or not text.strip():
                        pos, text = "bottom", rest
                    items.append({"kind": "caption", "start": float(start), "end": float(end),
                                  "pos": pos, "text": text.strip()})
                    continue
                w = shlex.split(line)
                if w[0] == "pad":
                    pre, post = float(w[1]), float(w[2])
                else:
                    items.append({"kind": "card", "start": float(w[1]), "end": float(w[2]),
                                  "title": w[3], "sub": w[4] if len(w) > 4 else ""})
            except (IndexError, ValueError):
                sys.exit(f"{path}:{n}: cannot read: {line}")
    return pre, post, items


def caption_png(text, W, H, out):
    s = W / 1600
    f = font("medium", round(30 * s))
    padx, pady, r = round(26 * s), round(16 * s), round(14 * s)
    maxw = W - round(160 * s)
    # Wrap on words to the box's width.
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if f.getlength(t) <= maxw - 2 * padx or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    asc, desc = f.getmetrics()
    lh = round((asc + desc) * 1.15)
    tw = max(f.getlength(l) for l in lines)
    bw, bh = round(tw + 2 * padx), lh * len(lines) + 2 * pady - (lh - asc - desc)
    sh = round(12 * s)  # room for the shadow
    img = Image.new("RGBA", (bw + 2 * sh, bh + 2 * sh), (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((sh, sh + 3, sh + bw, sh + bh + 3), r, fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(6 * s)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((sh, sh, sh + bw - 1, sh + bh - 1), r, fill=BG + (224,), outline=LINE + (255,), width=max(1, round(s)))
    for i, l in enumerate(lines):
        d.text((sh + padx, sh + pady + i * lh), l, font=f, fill=FG + (255,))
    img.save(out)
    return img.size


def card_png(title, sub, W, H, out):
    s = W / 1600
    img = Image.new("RGBA", (W, H), BG + (236,))
    d = ImageDraw.Draw(img)
    ft, fs = font("semibold", round(64 * s)), font("regular", round(30 * s))
    cy = H // 2
    tw = ft.getlength(title)
    d.text(((W - tw) / 2, cy - round(70 * s)), title, font=ft, fill=FG + (255,))
    d.rounded_rectangle(((W - 64 * s) / 2, cy + 8 * s, (W + 64 * s) / 2, cy + 12 * s), 2 * s, fill=PURPLE + (255,))
    if sub:
        d.text(((W - fs.getlength(sub)) / 2, cy + round(32 * s)), sub, font=fs, fill=SOFT + (255,))
    img.save(out)
    return img.size


def main():
    src, work, W, H, fps = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    pre, post, items = parse(src)
    os.makedirs(work, exist_ok=True)
    inputs, chain, last = [], [], "base"
    margin = round(48 * W / 1600)
    for i, it in enumerate(items):
        png = os.path.join(work, f"c{i:03d}.png")
        if it["kind"] == "card":
            w, h = card_png(it["title"], it["sub"], W, H, png)
            x, y = 0, 0
        else:
            w, h = caption_png(it["text"], W, H, png)
            x = (W - w) // 2
            y = {"bottom": H - h - margin, "top": margin, "center": (H - h) // 2}[it["pos"]]
        # Caption times are in recording time; the pre-pad shifts them.
        a, b = it["start"] + pre, it["end"] + pre
        dur = b - a
        fade = min(FADE, dur / 3)
        inputs += ["-loop", "1", "-framerate", fps, "-t", f"{dur:.3f}", "-i", png]
        k = i + 1
        chain.append(f"[{k}:v]format=rgba,fade=t=in:st=0:d={fade:.3f}:alpha=1,"
                     f"fade=t=out:st={dur - fade:.3f}:d={fade:.3f}:alpha=1,"
                     f"setpts=PTS-STARTPTS+{a:.3f}/TB[o{k}]")
        nxt = f"v{k}"
        chain.append(f"[{last}][o{k}]overlay=x={x}:y={y}:eof_action=pass:format=auto[{nxt}]")
        last = nxt
    head = f"[0:v]fps={fps},tpad=start_duration={pre}:start_mode=clone:stop_duration={post}:stop_mode=clone,format=yuv420p[base]"
    tail = f"[{last}]format=yuv420p[out]"
    with open(os.path.join(work, "inputs"), "w") as f:
        f.write("\n".join(inputs) + ("\n" if inputs else ""))
    with open(os.path.join(work, "filter"), "w") as f:
        f.write(";".join([head] + chain + [tail]))


main()
