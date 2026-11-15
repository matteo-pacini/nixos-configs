# Writes the launcher's emoji list: one "<emoji>\t<name>" line per
# fully-qualified emoji in emoji-test.txt, in file order, leaving out
# sequences with a skin-tone modifier (U+1F3FB..U+1F3FF).
#
# Regenerate from the pinned unicode-emoji package, at the repository root:
#   d=hosts/BrightFalls/users/matteo/hyprland
#   nix shell nixpkgs#python3 -c python3 -I $d/gen-emoji.py \
#     "$(nix eval --raw .#nixosConfigurations.BrightFalls.pkgs.unicode-emoji.outPath)/share/unicode/emoji/emoji-test.txt" \
#     $d/user/quickshell/launcher/emoji.txt

import sys

skin = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}
out = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        if line.startswith("#") or ";" not in line:
            continue
        codes, rest = line.split(";", 1)
        status, comment = rest.split("#", 1)
        if status.strip() != "fully-qualified":
            continue
        points = [int(c, 16) for c in codes.split()]
        if skin.intersection(points):
            continue
        # comment: " <emoji> E<version> <name>"
        _, _, name = comment.strip().split(" ", 2)
        out.append("".join(map(chr, points)) + "\t" + name)
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(len(out))
