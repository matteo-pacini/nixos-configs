# Agent instructions: legion-kvm

[legion-kvm](https://github.com/brcly/legion-kvm) runs Windows games through
Proton inside a KVM guest. This directory packages it, and
`modules/nixos/legion-kvm.nix` (`custom.legion-kvm`) installs it. Steam
launch options: `legion %command%`, with "GE-Proton11-11 (Legion)" as the
compatibility tool.

## Layout

Upstream builds one self-extracting executable in a Debian container, driven
by `tools/build_runtime.py`. This package splits that script's steps
into derivations:

| Upstream step | Here |
|---|---|
| `rust()` | `rust.nix`: glibc workspace, static musl launcher and guest init, `vhost-user-nvgpu` |
| `kernel()` | `kernel.nix`, which runs upstream's `kernel/build_guest.py` |
| `virgl()` | nixpkgs `virglrenderer` |
| `qemu()` | `qemu.nix`: nixpkgs `qemu.src`, plus upstream's patch and configure flags |
| `wine()` | `wine.nix`: the patched `ntdll.dll` |
| `radv()`, `guest_userspace()` | `guest.nix`: upstream's own functions, run in a Debian VM |
| `assemble()` | `default.nix` |

## Decisions

- **Unpacked runtime tree, no bundle.** The launcher treats the parent of its
  `bin/` as the runtime root. Every `runtime.json` asset must resolve inside
  that root, so files are copied in, never symlinked.
- **Host tools are Nix-built.** The private loader at
  `host/lib/ld-linux-x86-64.so.2` is a copy of glibc's. `host/lib` holds
  nothing else: the tools find their libraries through their RUNPATHs.
  Upstream's `config/host-packages.json` is unused.
- **The guest is Debian 13.** The guest programs hardcode Debian paths.
  `guest.nix`:
  - boots vmTools from the pinned closures in `debs-*.nix`;
  - trims `/usr/share/doc`, man pages and locales to match `debian:13-slim`;
  - calls upstream's `radv()` and `guest_userspace()` unchanged.
- **The guest's Rust programs are built with Nix and retargeted** to Debian's
  loader. The build fails if one needs a glibc symbol version newer than
  Debian's 2.41.
- **Proton is pinned by `config/compatibility.json`.** The Wine repair recipe
  only accepts that GE-Proton build, and `wine.nix` checks its hashes.
  `proton.nix` installs real files instead of store symlinks, because legion
  shares Proton into the guest over virtiofs.
- **vmTools gets stock QEMU.** The overlay entry passes it in, because
  BrightFalls' znver4 QEMU can't run on Nexus.
- **The final package uses `dontFixup`**, so Nix's fixup can't rewrite the
  Debian tree in `guest/usr`.

## Building

Prefer building on Nexus: `--max-jobs 0 --builders @/etc/nix/machines`. The
guest derivation needs the `kvm` system feature, which the Nexus builder
advertises.

## Bumping upstream

1. Update `rev`, `version` and `hash` in `source.nix`.
2. Diff upstream between the old and new rev, and mirror any changes:

   | Upstream file | Update here |
   |---|---|
   | `config/sources.json` | versions and hashes in `kernel.nix`, `wine.nix` and `guest.nix` (Mesa); copy the hex sha256 into `fetchurl` as is |
   | `config/compatibility.json` | the GE-Proton version and hash in `proton.nix` |
   | `build-support/Containerfile` | `debian-packages.nix`, then regenerate the closures |
   | `tools/build_runtime.py` | the matching derivation from the Layout table |
   | `src/runtime.rs` (`Manifest`) | the `runtime.json` fields in `default.nix` |

QEMU and virglrenderer come from nixpkgs, at the versions upstream pins.
`qemu.nix` asserts the QEMU version. virglrenderer has no assert, and it must
stay compatible with the guest's Mesa RADV.

Regenerate the Debian closures with:

```bash
nix build --impure -f packages/legion-kvm/debs-update.nix -o debs
cp debs/debs-*.nix packages/legion-kvm/
```

## Verifying

On the host: `legion doctor`, then `legion cpu-check`, which boots the
guest. In the `guest` output, `usr-manifest.json`'s
`optional_tool_dependencies_absent_in_full_baseline` should be empty.
