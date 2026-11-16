# mpv module

Home Manager module for mpv, derived from
[SoM-MPV-Config](https://github.com/JySzE/SoM-MPV-Config) ("SoM"), a
Windows-first mpv config pack. Options are under `custom.mpv`; see
`default.nix` for each one's description.

| Path | What |
|------|------|
| `default.nix` | Imports the rest; `enable`, the mpv package and its wrapper |
| `config.nix` | `mpv.conf` options |
| `profiles.nix` | Auto-profiles (SD upscale, primaries fixes, HDR and Dolby Vision tone mapping) |
| `bindings.nix` | `input.conf` bindings that differ from mpv's defaults |
| `scripts.nix` | Script options and the vendored files linked into `~/.config/mpv` |
| `assets/` | Vendored files, listed below |

## Provenance

The Nix files are a hand translation of SoM's config, with deliberate
changes (Vulkan and VideoToolbox instead of Direct3D, rewritten profile
conditions, pure white subtitles). The vendored files are copies; "SoM" in
the table is `JySzE/SoM-MPV-Config`.

| Local file | Upstream | Ref taken | Local modifications |
|------------|----------|-----------|---------------------|
| `assets/fonts/GandhiSans-*.otf` | SoM `fonts/` | `b6b94c216b` | None |
| `assets/menu.conf` | SoM `menu.conf` (1.0) | `b6b94c216b` | Open > Clipboard runs `update-clipboard text;` first, as mpv 0.42's stock `etc/menu.conf` does |
| `assets/scripts/osc.lua` | SoM `scripts/osc.lua`, itself [po5/thumbfast](https://github.com/po5/thumbfast) branch `vanilla-osc`, `player/lua/osc.lua` | `b6b94c216b` (= vanilla-osc `9d78edc167`) | None |
| `assets/scripts/persist-properties.lua` | SoM `scripts/persist-properties.lua`, SoM's edit of [d87/mpv-persist-properties](https://github.com/d87/mpv-persist-properties) | `b6b94c216b` | None |
| `assets/scripts/smart-native-screenshot.lua` | SoM branch `main-linux-wip`, `scripts/smart-native-screenshot.lua` (Linux 1, based on 1.4) | `0146b7a44b` | None |
| `assets/shaders/nnedi3-nns128-win8x6.hook` | SoM `shaders/`, itself [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) `master` | `b6b94c216b` (identical to prescalers `b3f0a59d68`) | None |
| `config.nix`, `profiles.nix` | SoM `mpv.conf` 3.6 | `b6b94c216b` | Translated by hand |
| `bindings.nix` | SoM `input.conf` 1.7 | `b6b94c216b` | Subset; right click left to mpv's default context menu |
| `scripts.nix` (thumbfast options) | SoM `script-opts/thumbfast.conf` | `b6b94c216b` | Subset, same values |

`thumbfast` and `autoload` come from nixpkgs (`pkgs.mpvScripts`), not from
SoM, and update with the flake.

## Checking for updates

SoM has no releases; each file carries a version and date in its header.
Compare against:

- SoM `main` for `menu.conf`, `input.conf`, `osc.lua`, fonts, shader and
  script options;
- SoM `main-linux-wip` for `mpv.conf` (its Linux version tracks `main`'s)
  and `smart-native-screenshot.lua`;
- po5/thumbfast `vanilla-osc`, d87/mpv-persist-properties `master` and
  bjin/mpv-prescalers `master` for the files SoM took from them;
- mpv's release notes (`DOCS/interface-changes.rst`) for renamed or
  deprecated options and bindings.

A vendored file is updated by copying it unchanged, then re-applying the
local modifications in the table. Update the ref column in the same commit.

Not taken from SoM `main` `10f9bf34a4`: the restyled `osc.lua` (it also
sets the idle window title to "SoM MPV"), `gifit.lua`, `center_vol.lua`
(it replaces the audio filter chain with a stereo downmix),
`limit-srt-lines.lua`, `script-opts/console.conf`, the OSD restyle and
subtitle margin changes in `mpv.conf`, and its two `8-Bit WEB-DL`
profiles (they match release-group names in the file name).
