# Guest userspace: a slice of Debian 13 /usr, as upstream's guest expects a
# Debian layout (hardcoded /usr/lib/x86_64-linux-gnu paths in the guest
# programs). Upstream's own radv() and guest_userspace() from
# tools/build_runtime.py run inside a Debian VM; only their inputs come from Nix.
{
  lib,
  stdenv,
  vmTools,
  fetchurl,
  patchelf,
  binutils,
  legionSource,
  rust,
  wine,
  proton,
}:
let
  # Debian's glibc. Guest programs built against Nix's newer glibc must not
  # need a symbol version beyond it. Only GLIBC_* versions are checked, not
  # GCC_* ones (libgcc_s, used by Rust's unwinder); the slim step catches
  # missing sonames but not missing symbol versions.
  debianGlibc = "2.41";

  image = vmTools.fillDiskWithDebs {
    name = "legion-kvm-guest-image";
    fullName = "Debian 13 (legion-kvm guest build)";
    size = 8192;
    memSize = 4096;
    debs = import ./debs-amd64.nix { inherit fetchurl; };
  };

  i386Debs = lib.flatten (import ./debs-i386.nix { inherit fetchurl; });

  # Hash from upstream's config/sources.json.
  mesa = fetchurl {
    url = "https://deb.debian.org/debian/pool/main/m/mesa/mesa_25.0.7.orig.tar.xz";
    sha256 = "592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6";
  };

  # Retarget the Nix-built guest programs at Debian's loader and library path.
  programs = stdenv.mkDerivation {
    name = "legion-kvm-guest-programs";
    nativeBuildInputs = [
      patchelf
      binutils
    ];
    dontUnpack = true;
    dontPatchELF = true;
    dontStrip = true;
    installPhase = ''
      mkdir -p $out/release
      for path in bin/legion-proton-bootstrap bin/legion-guest-compositor bin/legion-audio-runtime \
                  bin/legion-cpu-adapter-fixture lib/liblegion_cpu_adapter.so; do
        target=$out/release/$(basename $path)
        install -m0755 ${rust.workspace}/$path $target
        newest=$(objdump -T $target | { grep -oE 'GLIBC_[0-9.]+' || true; } | sed 's/GLIBC_//' | sort -V | tail -1)
        if [ "$(printf '%s\n' "$newest" ${debianGlibc} | sort -V | tail -1)" != ${debianGlibc} ]; then
          echo "$path needs GLIBC_$newest, newer than Debian's ${debianGlibc}" >&2
          exit 1
        fi
        patchelf --remove-rpath $target
        case $path in bin/*) patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $target ;; esac
      done
    '';
  };
in
vmTools.runInLinuxImage (
  stdenv.mkDerivation {
    name = "legion-kvm-guest-userspace";
    diskImage = image;
    # Sized to fit a GitHub ubuntu-24.04 runner (4 vCPUs, 16 GB), which builds
    # BrightFalls in CI.
    memSize = 8192;
    QEMU_OPTS = "-smp 4";
    buildCommand = ''
      set -euo pipefail
      for deb in ${toString i386Debs}; do
        dpkg-deb --fsys-tarfile $deb | tar -x --keep-directory-symlink -C /
      done
      ldconfig
      # Match the debian:13-slim base upstream builds from: its dpkg config keeps
      # only copyright files under /usr/share/doc, and no man pages or locales.
      # The slim step copies share/doc whole and fails on full Debian's
      # doc-directory symlinks.
      find /usr/share/doc -mindepth 1 \( -type l -o \( -type f ! -name copyright \) \) -delete
      find /usr/share/doc -mindepth 1 -type d -empty -delete
      rm -rf /usr/share/man /usr/share/groff /usr/share/info /usr/share/lintian /usr/share/linda
      find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name locale.alias -exec rm -rf {} +

      work=/tmp/legion
      mkdir -p $work/wine/dlls/ntdll/x86_64-windows $work/sources/mesa
      cp ${wine}/ntdll.dll $work/wine/dlls/ntdll/x86_64-windows/ntdll.dll
      tar -xf ${mesa} --strip-components=1 -C $work/sources/mesa
      # guest_userspace() reads the Proton tree from /proton.
      ln -s ${proton.src} /proton

      python3 - <<'PY'
      import sys
      from pathlib import Path
      sys.path.insert(0, '${legionSource.src}/tools')
      import build_runtime as br
      br.ROOT = Path('${legionSource.src}')
      br.OUT = Path('/tmp/legion')
      br.TARGET = Path('${programs}')
      br.JOBS = 4
      br.radv(br.OUT/'sources/mesa')
      br.guest_userspace()
      PY

      mkdir -p $out
      cp -dR --preserve=mode,timestamps $work/usr $out/usr
      cp $work/usr-manifest.json $out/
    '';
  }
)
