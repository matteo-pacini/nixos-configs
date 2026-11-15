# Agent instructions: legion-kvm

[legion-kvm](https://github.com/brcly/legion-kvm) runs Windows games through
Proton inside a KVM guest. This directory packages it, and
`modules/nixos/legion-kvm.nix` (`custom.legion-kvm`) installs it. Steam
launch options: `legion %command%`. Games render through Mesa Venus: the
guest's Vulkan calls run on the host's Vulkan driver (RADV here) through
virglrenderer.

## Layout

Upstream builds one self-extracting executable in a Debian container, driven
by `tools/build_runtime.py`. This package splits that script's steps
into derivations:

| Upstream step | Here |
|---|---|
| `rust()` | `rust.nix`: glibc guest programs, static musl launcher and guest init |
| `kernel()` | `kernel.nix`, which runs upstream's `kernel/build_guest.py` |
| `virgl()` | `virglrenderer.nix`: nixpkgs `virglrenderer` plus upstream's Venus patches |
| `qemu()` | `qemu.nix`: nixpkgs `qemu.src`, plus upstream's patches and configure flags |
| `wine()` | not built: the optional Wine repair is left out |
| `venus()`, `guest_userspace()` | `guest.nix`: upstream's own functions, run in a Debian VM |
| `assemble()` | `default.nix` |

## Decisions

- **Unpacked runtime tree, no bundle.** The launcher treats the parent of its
  `bin/` as the runtime root. Every `runtime.json` asset must resolve inside
  that root, so files are copied in, never symlinked.
- **Host tools are Nix-built.** The private loader at
  `host/lib/ld-linux-x86-64.so.2` is a copy of glibc's. `host/lib` holds
  nothing else: the tools find their libraries through their RUNPATHs.
  Upstream's `config/host-packages.json` is unused, and so is its bundled
  `libwayland-client`, which breaks host EGL upstream.
- **The render server's device-select layer is nixpkgs Mesa's.** The
  launcher runs `virgl_render_server` with `VK_LAYER_PATH=host/vulkan` and
  only that layer enabled. Upstream copies the layer from its guest Mesa
  build; here `host/vulkan` holds nixpkgs Mesa's manifest, which points at
  the store. The Vulkan driver itself comes from `/run/opengl-driver`.
- **The guest is Debian 13.** The guest programs hardcode Debian paths.
  `guest.nix`:
  - boots vmTools from the pinned closures in `debs-*.nix`;
  - trims `/usr/share/doc`, man pages and locales to match `debian:13-slim`;
  - calls upstream's `venus()` and `guest_userspace()` unchanged.
- **The guest's Rust programs are built with Nix and retargeted** to Debian's
  loader. The build fails if one needs a glibc symbol version newer than
  Debian's 2.41.
- **No Wine repair.** Upstream made its patched `ntdll.dll` optional
  (`--wine-repair` at build time, `LEGION_WINE_REPAIR=1` at launch) and off by
  default, so this package doesn't build it, and `LEGION_WINE_REPAIR=1`
  fails. Any Proton with Wine Wayland support works.
- **GE-Proton11-11 is still installed** (`proton.nix`), as "GE-Proton11-11
  (Legion)". The guest build scans it for the libraries Proton needs, and it
  is the Proton tested here. It holds real files instead of store symlinks,
  because legion shares Proton into the guest over virtiofs.
- **vmTools gets stock QEMU.** The overlay entry passes it in, because
  BrightFalls' znver4 QEMU can't run on Nexus. The guest build VM is sized
  (8 GiB, 4 vCPUs) to fit the GitHub runner that builds BrightFalls in CI.
- **The Cargo lock file is copied in** (`Cargo.lock`), so evaluating BrightFalls doesn't need to fetch the upstream source first.
- **The final package uses `dontFixup`**, so Nix's fixup can't rewrite the
  Debian tree in `guest/usr`.
- **The launcher makes its session copies writable**
  (`patches/legion-001-writable-session-copies.patch`). Each launch copies `guest/usr` with
  `cp -a`, which keeps the store's 0555 modes, then writes into it. `cp --no-preserve=mode` would drop execute bits.
  `legion doctor` and `cpu-check` don't copy, so only a real launch shows
  this.
- **Launcher-only changes live in `rust.nix` `static`**: the launcher's
  `legion-*` patches and the `game.rs` substitutions (resolution, default
  memory, default fullscreen). Changing them rebuilds only the launcher and
  the final package, not the guest. Guest-side patches go on `workspace`,
  which rebuilds the guest.
- **Keyboard, mouse and cursor are upstream's.** QEMU gets a virtio keyboard
  and a virtio tablet (absolute pointer), and with `LEGION_DESKTOP_INPUT`
  its SDL window grabs neither, so host shortcuts keep working. The guest
  compositor reads the evdev nodes and puts the client's cursor on
  virtio-gpu's cursor plane.
- **Game resolution is patched in.** Upstream hardcodes the guest display at
  1920x1080. `src/game.rs` writes it to `kms.json`, which becomes
  QEMU's virtio-gpu `xres`/`yres`. `rust.nix` substitutes the module's
  `resolution` (default 1920x1080; BrightFalls sets 2560x1440). Upstream caps
  it at 3840x2160. The QEMU window is
  resizable, and QEMU passes its size to the guest as the new preferred mode.
  A windowed 2560x1440 gets shrunk to the desktop's work area, so a
  desktop-sized resolution needs `fullscreen` (BrightFalls sets it).
- **vCPUs can be pinned to the host topology** (`pinVcpus`; BrightFalls on).
  Upstream mirrors the host's socket/core/SMT shape in `-smp` but leaves
  vCPU threads floating. `legion-003-vcpu-affinity-env.patch` makes the
  launcher set `LEGION_VCPU_AFFINITY`: the host CPU for each vCPU,
  in QEMU's cpu_index order. `qemu-001-vcpu-affinity.patch` makes each vCPU thread
  pin itself to its entry. QEMU always carries its patch, which does nothing
  without the variable, so toggling the option rebuilds only the launcher.
- **The default guest memory is patched** to the module's `memoryMiB`
  (upstream 12288; BrightFalls 16384). The launcher refuses to start unless
  MemAvailable covers it plus 2048 MiB.
- **The refresh rate is patched in too.** No vblank paces the guest: virtio-gpu
  page flips complete when the host takes the frame, and QEMU's SDL window
  swaps with interval 0. But the guest display's EDID advertises QEMU's
  fallback of 75 Hz, because SDL never passes a refresh rate. That caps any
  game or limiter that follows the display's refresh rate. `qemu.nix`
  substitutes the module's `refreshRate` for that fallback (default 75;
  BrightFalls sets 144). The mode is the EDID's preferred timing either way,
  so the guest kernel lists it first. That's a base-EDID timing, or a
  DisplayID block once the pixel clock reaches 655.36 MHz (2560x1440 from
  about 128 Hz).

## Our changes to upstream

Patch files live in `patches/` as `<target>-<NNN>-<what>.patch`: `target` is
the tree they patch (`legion` for upstream's source, `qemu`, `virgl`), and
`NNN` is the order they apply in. Changes that insert module option values
stay as substitutions in the `.nix` files.

| Where | Change | Applied |
|---|---|---|
| `patches/legion-001-writable-session-copies.patch` | `chmod -R u+w` the launcher's session copies | always |
| `patches/legion-002-sdl-gles-display.patch` | QEMU `-display sdl,gl=es` instead of `gl=on`: the desktop window imports frames as `GL_TEXTURE_EXTERNAL_OES`, which Mesa only supports in GLES, so `gl=on` showed a black window on the native-context path | always |
| `patches/legion-003-vcpu-affinity-env.patch` | launcher sets `LEGION_VCPU_AFFINITY` | `pinVcpus` |
| `patches/legion-007-qemu-parent-death-signal.patch` | QEMU gets SIGKILL if the launcher dies, so its window can't outlive it | always |
| `patches/virgl-001-device-groups-filter.patch` | the render server drops GPUs it never enumerated from `vkEnumeratePhysicalDeviceGroups`. Mesa's device-select layer narrows the device list to the selected GPU but passes every group through, so on a host with several GPUs (BrightFalls: RX 6800 XT, 780M, llvmpipe) Venus failed with "venus driver is required to call vkEnumeratePhysicalDevices first" | always |
| `patches/qemu-001-vcpu-affinity.patch` | vCPU threads pin themselves from `LEGION_VCPU_AFFINITY` | always (inert without it) |
| `rust.nix` substitution, `src/game.rs` | game display size | always (`resolution`) |
| `rust.nix` substitution, `src/game.rs`, `src/main.rs` | default `LEGION_MEMORY_MIB` | always (`memoryMiB`) |
| `rust.nix` substitution, `src/game.rs` | fullscreen unless `LEGION_FULLSCREEN` is set to something other than 1 | `fullscreen` |
| `qemu.nix` substitution, `hw/display/edid-generate.c` | EDID fallback refresh rate | always (`refreshRate`) |

Environment variables read at launch:

| Variable | Effect |
|---|---|
| `LEGION_FULLSCREEN` | `1` fullscreen; anything else windowed (default from `fullscreen`) |
| `LEGION_MEMORY_MIB` | guest memory, 4096–65536 (default from `memoryMiB`) |
| `LEGION_RENDER_NODE` | DRM render node, for hosts with several GPUs |
| `LEGION_STARTUP_UI` | `auto`, `window`, `log` or `off` startup feedback |
| `LEGION_STARTUP_TIMEOUT_SECONDS` | time allowed to the first frame, 30–900 (default 180) |
| `LEGION_WINDOW_SYSTEM` | host window: `auto` (Wayland, XWayland if that fails), `wayland` or `x11` |
| `MANGOHUD` | `1` turns on MangoHud in the guest |
| `LEGION_VCPU_AFFINITY` | ours, internal: set by the launcher for QEMU, not by hand |

## Building

Prefer building on Nexus: `--max-jobs 0 --builders @/etc/nix/machines`. The
guest derivation needs the `kvm` system feature, which the Nexus builder
advertises.

## Bumping upstream

1. Update `rev`, `version` and `hash` in `source.nix`, and copy upstream's
   `Cargo.lock` over `Cargo.lock`.
2. Diff upstream between the old and new rev, and mirror any changes:

   | Upstream file | Update here |
   |---|---|
   | `config/sources.json` | versions and hashes in `kernel.nix` and `guest.nix` (Mesa); copy the hex sha256 into `fetchurl` as is |
   | `build-support/Containerfile` | `debian-packages.nix`, then regenerate the closures |
   | `tools/build_runtime.py` | the matching derivation from the Layout table |
   | `src/runtime.rs` (`Manifest`) | the `runtime.json` fields in `default.nix` |
   | `src/`, `crates/guest-compositor/`, `crates/proton-workload/src/bootstrap.rs` | the `patches/legion-*` patches and the `rust.nix` substitutions. A failed patch or `--replace-fail` breaks the build; drop a substitution if upstream adds a setting for it |

QEMU and virglrenderer come from nixpkgs, at the versions upstream pins;
`qemu.nix` and `virglrenderer.nix` assert them. virglrenderer must stay
compatible with the guest's Mesa Venus.

Regenerate the Debian closures with:

```bash
nix build --impure -f packages/legion-kvm/debs-update.nix -o debs
cp debs/debs-*.nix packages/legion-kvm/
```

## Known gaps

- **No controllers:** no gamepad events in the display channel, and no USB, HID or joystick support in the guest kernel.

## Verifying

On the host: `legion doctor`, then `legion cpu-check`, which boots the
guest. In the `guest` output, `usr-manifest.json`'s
`optional_tool_dependencies_absent_in_full_baseline` should be empty.

`legion doctor --graphics` boots a throwaway VM, opens the window and checks
that the guest enumerates the host GPU through Venus. It doesn't render a
game.

A non-Steam game, The Darkness Recomp for example, launches with:

```bash
legion run --proton <GE-Proton11-11 compat tool> --prefix <new dir> \
  --game-root <game> -- <game>/build_native/Release/DarkRecomp.exe \
  --game-dir 'Z:\<game path>\Darkness'
```

Legion starts the app in the exe's folder, not the game root. The guest
mirrors host paths, so `Z:\` plus the host path reaches the game's files.
