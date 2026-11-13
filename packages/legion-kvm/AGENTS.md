# Agent instructions: legion-kvm

[legion-kvm](https://github.com/brcly/legion-kvm) runs Windows games through
Proton inside a KVM guest. This directory packages it, and
`modules/nixos/legion-kvm.nix` (`custom.legion-kvm`) installs it. Only
BrightFalls enables it, in `hosts/BrightFalls/gaming.nix`. Repo-wide rules are
in the root `AGENTS.md`.

Usage: set a game's Steam launch options to `legion %command%` and its
compatibility tool to "GE-Proton11-11 (Legion)". The launcher keeps its cache
in `~/.cache/legion` and logs and runs in `~/.local/state/legion`.

## How upstream builds it, and how this differs

Upstream's `tools/build.py` builds one self-extracting executable inside a
Debian 13 container (`build-support/Containerfile`). The container
downloads sources at build time and installs Rust with rustup.
`tools/build_runtime.py` is the real build script. This package mirrors its
steps:

| Upstream step (`build_runtime.py`) | Here | Built by |
|---|---|---|
| `rust()`: glibc workspace | `rust.nix` `workspace` | Nix |
| `rust()`: musl `legion` and `legion-guest-probe` | `rust.nix` `static` (pkgsStatic) | Nix |
| `rust()`: `vhost-user-nvgpu` | `rust.nix` `vhost-user-nvgpu` | Nix |
| `kernel()`: guest kernel and out-of-tree modules | `kernel.nix`, which runs upstream's `kernel/build_guest.py` | Nix |
| `virgl()` | nixpkgs `virglrenderer`, already built with `amdgpu-experimental` | Nix |
| `qemu()` | `qemu.nix`: nixpkgs `qemu.src`, upstream's patch and configure flags | Nix |
| `wine()`: patched `ntdll.dll` | `wine.nix` | Nix |
| `radv()` and `guest_userspace()` | `guest.nix`, which calls upstream's own functions inside a Debian VM | vmTools |
| `assemble()` | `default.nix` | Nix |
| `package()`: self-extracting bundle | not done | n/a |

## Decisions

- **No bundle; the runtime tree is installed unpacked.** The launcher looks
  for `runtime.json` and `bin/legion` under the parent of its own `bin/`
  (`src/packed.rs`, `src/runtime.rs` `Runtime::load`), so `$out` is the
  runtime root. Every asset path in `runtime.json` must canonicalize to a
  path inside that root (`Runtime::asset`). Symlinks into other store paths
  are rejected, so files are copied in.
- **Host binaries are linked against Nix, and `host/lib` is empty.** The
  launcher always starts QEMU, virtiofsd and the backend as
  `host/lib/ld-linux-x86-64.so.2 --library-path host/lib <tool>`. That
  loader is a copy of the system glibc's `ld.so`. The tools resolve their
  libraries through their RUNPATHs. Upstream's `config/host-packages.json`
  (Arch glibc, libgcc, libdrm, libstdc++) exists so a binary built on one
  distro can load another distro's GPU drivers. That doesn't apply here: the
  package and the system's Mesa come from the same nixpkgs. So that file is
  unused.
- **The guest userspace is Debian, not Nix.** The guest programs hardcode
  Debian paths (`/usr/lib/x86_64-linux-gnu/...`, `/usr/bin/Xwayland`,
  `/usr/bin/python3`), and `tools/prepare_slim_userspace.py` builds the guest
  by trimming a Debian `/usr`. `guest.nix` therefore:
  - boots a vmTools VM from `debs-amd64.nix`;
  - unpacks the i386 debs from `debs-i386.nix` without installing them (the
    image has no i386 dpkg architecture);
  - sets `ROOT`, `OUT`, `TARGET` and `JOBS` on `build_runtime.py`, then calls
    `radv()` and `guest_userspace()` unchanged. Upstream's logic is reused,
    not reimplemented.
- **The deb closures are pinned in the repo.** `debs-amd64.nix` and
  `debs-i386.nix` come from `vmTools.debClosureGenerator`. Checking them in
  avoids import-from-derivation at eval. Regenerate them with
  `debs-update.nix`, never by hand.
- **The guest's `/usr/share/doc`, man pages and locales are trimmed to match
  `debian:13-slim`.** The slim step copies `share/doc` whole, and it fails on
  full Debian's symlinked doc directories. Upstream's base image never has
  them.
- **The guest's Rust programs are built with Nix and retargeted.** They are
  pure Rust plus SDL2, xkbcommon and ALSA. `guest.nix`:
  - points them at Debian's `/lib64/ld-linux-x86-64.so.2`;
  - removes their RUNPATH;
  - fails if any of them needs a glibc symbol version newer than Debian's
    2.41 (`debianGlibc`). Nix's glibc is newer.
- **GE-Proton11-11 is pinned and installed as real files.**
  - The runtime ships `wine-repair.json`, a recipe that rebuilds our
    `ntdll.dll` from the selected Proton's own copy. It is only valid for the
    Proton named by the hashes in `config/compatibility.json`, and
    `wine.nix` checks those hashes.
  - legion shares the selected Proton directory into the guest over
    virtiofs, where `/nix/store` doesn't exist. So `proton.nix` copies the
    files instead of using `proton-ge-bin`'s symlinks, and it shows in Steam
    under its own display name.
- **Wine is built with nixpkgs clang, not Debian's.** The PE side uses
  clang and lld with no mingw, like upstream. The recipe is about 95%
  literal bytes, so it effectively carries our whole DLL. Codegen
  differences from upstream's tested build are untested.
- **vmTools needs a stock QEMU.** vmTools boots with
  `buildPackages.qemu_kvm`. On BrightFalls that derives from the znver4 QEMU
  in `overlays/brightfalls.nix`, which crashes with an illegal instruction on
  Nexus. The overlay entry for `legion-kvm` passes a vmTools with stock QEMU
  instead. `qemu_kvm` isn't overridden globally because libvirtd uses it.
- **`dontFixup` on the final package.** `guest/usr` is a Debian tree:
  patchelf, strip and patchShebangs would point it at `/nix/store`.
- **The NVIDIA backend is built but unused on BrightFalls.** BrightFalls is
  AMD, and the AMD native-context path is the one in use. `runtime.json`
  still lists the NVIDIA assets because upstream's manifest expects them.

## Building

Build on Nexus, not locally (the BrightFalls root disk is nearly full).
The guest derivation needs the `kvm` system feature. The Nexus builder entry advertises
it (`modules/shared/nexus-builder.nix`), but only once that change has been
deployed to the host you build from. Until then, pass a builder string that
includes `kvm`:

```bash
nix build --max-jobs 0 \
  --builders 'ssh-ng://matteo@nexus-ts.walrus-draconis.ts.net:1788 x86_64-linux /home/matteo/.ssh/mesh 8 100 big-parallel,benchmark,kvm - -' \
  .#nixosConfigurations.BrightFalls.pkgs.legion-kvm
```

Each piece is exposed through `passthru` for building on its own: `proton`,
`rust.{workspace,static,vhost-user-nvgpu}`, `kernel`, `qemu`, `wine` and
`guest`. CI opens `/dev/kvm` on Linux runners
(`.github/workflows/{build,pr-build,build-package}.yml`). Nix only advertises
`kvm` when `/dev/kvm` is readable and writable at startup.

A full build compiles Mesa RADV, the guest kernel and Wine, so push the
outputs to attic afterwards:

```bash
p=.#nixosConfigurations.BrightFalls.pkgs.legion-kvm
nix build --max-jobs 0 --builders '...' \
  $p $p.proton.steamcompattool $p.guest $p.kernel $p.qemu $p.wine \
  $p.rust.workspace $p.rust.static $p.rust.vhost-user-nvgpu -o result-legion-kvm
attic push main ./result-legion-kvm*
```

## Bumping upstream

1. Diff upstream between the pinned `rev` in `source.nix` and the new one.
   These files each map onto something here:

   | Upstream file | Update here |
   |---|---|
   | `config/sources.json` | each source's version, URL and sha256: `kernel.nix` (linux), `wine.nix` (wine), `guest.nix` (mesa). QEMU and virglrenderer come from nixpkgs; see below. |
   | `config/compatibility.json` | the Proton version: see "Bumping Proton" |
   | `build-support/Containerfile` | `debian-packages.nix`, then regenerate the closures |
   | `tools/build_runtime.py` `qemu()` | the configure flags and patch list in `qemu.nix` |
   | `tools/build_runtime.py` `wine()` | the configure flags in `wine.nix` |
   | `tools/build_runtime.py` `rust()` | the cargo flags and outputs in `rust.nix` |
   | `tools/build_runtime.py` `kernel()` | the module list and ordering in `kernel.nix` |
   | `tools/build_runtime.py` `guest_userspace()` | the programs list in `guest.nix` |
   | `tools/build_runtime.py` `assemble()` | the module order, `runtime.json` and the file layout in `default.nix` |
   | `src/runtime.rs` (`Manifest`) | the `runtime.json` fields in `default.nix` |
   | `rust-toolchain.toml` | check that nixpkgs `rustc` is at least that version |

2. Update `rev` and `version` in `source.nix`. Set `hash` to the fake hash
   (`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`), build, and copy in
   the `got:` hash.
3. Build the full package on Nexus, then verify (below).

`sources.json` records hex SHA-256s, and `fetchurl`'s `sha256 =` takes that
hex string as is, so copy the value over unchanged.

### QEMU and virglrenderer

Both come from nixpkgs, because nixpkgs shipped the exact versions upstream
pins: QEMU 11.1.2 and virglrenderer 1.3.0. `qemu.nix` asserts the QEMU
version, so a nixpkgs bump fails at eval instead of building a different
QEMU. When that assert fires:
- if upstream moved to the same version, update the assert;
- otherwise, fetch upstream's tarball (URL and hash in `sources.json`) in
  `qemu.nix` instead of `qemu.src`.

virglrenderer has no assert. It speaks the native-context protocol with the
guest's Mesa RADV, so if nixpkgs changes its version, check it against the
version in upstream's `sources.json`.

### Bumping Proton

The Proton version is set by upstream's `config/compatibility.json`. It is
not a free choice. When those hashes change:

- find the GE-Proton release whose
  `files/lib/wine/x86_64-windows/ntdll.dll` and
  `files/lib/wine/x86_64-unix/ntdll.so` match them;
- set `version` and the `fetchzip` hash in `proton.nix`, and the display
  name, which includes the version;
- update the compat tool name in the module's option description and in this
  file.

`wine.nix` fails the build if the hashes don't match.

### Regenerating the Debian closures

After changing `debian-packages.nix`:

```bash
nix build --impure -f packages/legion-kvm/debs-update.nix -o debs
cp debs/debs-*.nix packages/legion-kvm/
```

The closures come from the snapshot.debian.org timestamp that nixpkgs'
`vmTools.debDistros.debian13*` uses. Snapshot URLs are permanent, so the
checked-in files stay valid across nixpkgs bumps.

`debs-update.nix` also fetches trixie's `contrib` Packages.xz with its own
hash, because `libnvidia-egl-gbm1` lives in contrib. If nixpkgs moves to a
newer snapshot, regenerating fails on that hash; update it.

If the closure generator reports `unknown (virtual) package X`, the package
is not in that archive area or under that name.

## Verifying

On BrightFalls, after a deploy or with the built store path:

```bash
legion --version
legion doctor     # checks KVM, graphics, the desktop, QEMU and virtiofsd
legion cpu-check  # boots the guest kernel and init under KVM
```

These don't run a game; launch one from Steam with the options under
"Usage". `usr-manifest.json` in the `guest` output lists the optional
libraries the slim step couldn't find
(`optional_tool_dependencies_absent_in_full_baseline`). Keep that list empty
by adding the Debian packages that provide them.
