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
| `jellyfin-shim.nix` | `custom.mpv.jellyfinShim`: jellyfin-mpv-shim, its config files and login autostart (see below) |
| `assets/` | Vendored files, listed below |

## jellyfin-mpv-shim

Enabled on BrightFalls, NightSprings and WorkLaptop. The package comes from
nixpkgs with a local patch (`overlays/shared.nix`, health check). The module
links the mpv files from `~/.config/mpv` into the shim's config directory,
because the shim gives mpv its own config directory and never reads
`~/.config/mpv`. It also writes the Dracula theme and seeds `conf.json` once.
It starts the shim minimised at login.

| | Linux (BrightFalls) | macOS (NightSprings, WorkLaptop) |
|---|---|---|
| Config directory | `~/.config/jellyfin-mpv-shim` | `~/Library/Application Support/jellyfin-mpv-shim` |
| Autostart | systemd user service on `graphical-session.target`, `Restart=on-failure` | launchd agent in the Aqua session, restarted unless it exits cleanly (Quit) |
| Player | libmpv inside the shim | an external `mpv` process (the shim's default on macOS), nixpkgs' mpv from the package wrapper's `PATH` |
| GPU | `MESA_VK_DEVICE_SELECT=discrete!` in the unit | none |
| Tray | the Quickshell bar (the unit is ordered after it) | the menu bar |
| Package | nixpkgs plus the patch | also lifts nixpkgs' Linux-only platform list and skips python-mpv's tests, which cannot run in the Darwin build sandbox |

The player in both cases is nixpkgs' plain mpv, not the `programs.mpv`
wrapper, so `thumbfast` and `autoload` do not load in the shim.

Activation also repairs an existing `conf.json` in one way: if
`mpv_ext_path` holds a `/nix/store/` path, it is set to `null`, which makes
the shim take `mpv` from its `PATH`. An older version of this module seeded
that key with a store path; since Nix does not track the file, the path
outlives its store entry, and on macOS the shim then fails to start its
external mpv and launchd restarts it every 10 seconds. Every other key is
kept, the file keeps its mode, and a missing or unparsable file is left
alone. The step runs before Home Manager (re)loads the launchd agent or the
systemd units, on both platforms (on Linux the key is unused while the shim
plays through libmpv, but a store path there would be just as stale).

## Provenance

The Nix files are a hand translation of SoM's config, with deliberate
changes (Vulkan and VideoToolbox instead of Direct3D, rewritten profile
conditions, pure white subtitles). The vendored files are copies; "SoM" in
the table is `JySzE/SoM-MPV-Config`.

| Local file | Upstream | Ref taken | Local modifications |
|------------|----------|-----------|---------------------|
| `assets/fonts/GandhiSans-*.otf` | SoM `fonts/` | `b6b94c216b` | None |
| `assets/menu.conf` | SoM `menu.conf` (1.0) | `b6b94c216b` | Open > Clipboard runs `update-clipboard text;` first, as mpv 0.42's stock `etc/menu.conf` does |
| `assets/scripts/osc.lua` | SoM `scripts/osc.lua`, itself [po5/thumbfast](https://github.com/po5/thumbfast) branch `vanilla-osc`, `player/lua/osc.lua` | `b6b94c216b` (= vanilla-osc `9d78edc167`) | Dracula colours in `osc_styles`: `box`, `timePosBar` outline and `wcBar` in background, `elementDown` in comment, and a new `seekbarFillBar` style (purple) that the bottombar `seekbar` uses instead of `timecodesBar` |
| `assets/scripts/persist-properties.lua` | SoM `scripts/persist-properties.lua`, SoM's edit of [d87/mpv-persist-properties](https://github.com/d87/mpv-persist-properties) | `b6b94c216b` | None |
| `assets/scripts/smart-native-screenshot.lua` | SoM branch `main-linux-wip`, `scripts/smart-native-screenshot.lua` (Linux 1, based on 1.4) | `0146b7a44b` | None |
| `assets/shaders/nnedi3-nns128-win8x6.hook` | SoM `shaders/`, itself [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) `master` | `b6b94c216b` (identical to prescalers `b3f0a59d68`) | None |
| `config.nix`, `profiles.nix` | SoM `mpv.conf` 3.6; then, from `main-linux-wip`'s `mpv.conf` Linux 1.9 (= `main` 4.6), only the `PGS Scaling` profile, SD `scale-antiring=0`, HDR `screenshot-sw=yes` and the subtitle margins (`sub-use-margins=yes`, `sub-margin-y=50`, no `blend-subtitles`) | `b6b94c216b`, then `0146b7a44b` | Translated by hand |
| `bindings.nix` | SoM `input.conf` 1.7 | `b6b94c216b` | Subset; right click left to mpv's default context menu |
| `scripts.nix` (thumbfast options) | SoM `script-opts/thumbfast.conf` | `b6b94c216b` | Subset, same values |

`thumbfast` and `autoload` come from nixpkgs (`pkgs.mpvScripts`), not from
SoM, and update with the flake.

## Theme

The player chrome uses Dracula, with the palette of the BrightFalls desktop
(`hosts/BrightFalls/users/matteo/hyprland/user/quickshell/Theme.qml`) and
purple as the accent:

- `config.nix`: OSD font (Fira Sans, shipped into `~~/fonts` by `scripts.nix`
  so every host has it), text and outline colours, and the selected-item
  colour. The OSD bar has no colour option and follows the OSD text colour.
- `scripts.nix`: `osc.boxalpha`, and the colours of the console and select
  menus, the right-click context menu and the stats graphs.
- `assets/scripts/osc.lua`: the OSC's colours are hard-coded, so they are a
  local modification (see the table above).
- `jellyfin-shim.nix`: `themes/dracula.json` for the shim's library browser,
  selected in the seeded `conf.json`. An existing `conf.json` keeps its
  theme; pick it once in the shim's settings.

Not themed, on purpose: subtitles (pure white), the window background and
letterbox bars (black; no `background-color`), the OSC idle logo (mpv's
brand colours), and the shim's player HUD panel (hard-coded in the shim).

## GPU

On Linux, the mpv wrapper (`default.nix`) and the shim's systemd unit
(`jellyfin-shim.nix`) both set `MESA_VK_DEVICE_SELECT=discrete!`. The
wrapper sets it with `--set` (not `--set-default`), which overrides the
caller's environment, so testing on the integrated GPU needs the unwrapped binary the
wrapper execs (`MESA_VK_DEVICE_SELECT='integrated!' <unwrapped mpv>
--hwdec=vulkan <file>`); the variable in front of `mpv` has no effect.

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
`limit-srt-lines.lua`, `script-opts/console.conf`, the OSD restyle in
`mpv.conf`, and its two `8-Bit WEB-DL` profiles (they match release-group
names in the file name).
