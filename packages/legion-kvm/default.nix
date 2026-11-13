# Legion KVM: runs Windows games through Proton inside a KVM guest.
# https://github.com/brcly/legion-kvm
#
# Upstream ships one self-extracting executable built in a Debian container.
# This installs the same runtime tree unpacked: the launcher uses a runtime.json
# next to its own bin/ directly. Host binaries are built with Nix; the guest
# userspace comes from Debian 13 (guest.nix).
{
  lib,
  stdenv,
  callPackage,
  vmTools,
  glibc,
  virtiofsd,
  # Guest display mode for games on the AMD path. Upstream accepts up to
  # 3840x2160.
  resolution ? {
    width = 1920;
    height = 1080;
  },
}:
assert resolution.width >= 64 && resolution.width <= 3840;
assert resolution.height >= 64 && resolution.height <= 2160;
let
  legionSource = callPackage ./source.nix { };
  proton = callPackage ./proton.nix { };
  rust = callPackage ./rust.nix { inherit legionSource resolution; };
  kernel = callPackage ./kernel.nix { inherit legionSource; };
  qemu = callPackage ./qemu.nix { inherit legionSource; };
  wine = callPackage ./wine.nix { inherit legionSource proton; };
  guest = callPackage ./guest.nix {
    inherit
      vmTools
      legionSource
      rust
      wine
      proton
      ;
  };

  # Module order and numbering follow build_runtime.py assemble().
  nvidiaModules = [
    "virtio_gpu_nv"
    "legion_cpuid"
    "ntsync"
  ];
  amdModules = [
    "virtio_dma_buf"
    "drm_shmem_helper"
    "drm_kms_helper"
    "virtio-gpu"
    "legion_cpuid"
    "ntsync"
  ];
  modules = lib.unique (nvidiaModules ++ amdModules);
  modulePath =
    name:
    "guest/modules/${lib.fixedWidthNumber 3 (lib.lists.findFirstIndex (m: m == name) null modules)}.ko";

  common = {
    qemu = "libexec/qemu-system-x86_64";
    kernel = "guest/kernel";
    init = "guest/init";
    # Every asset must resolve inside the runtime root, so the loader is a
    # copy. host/lib stays otherwise empty: the Nix-built tools carry RUNPATHs.
    host_loader = "host/lib/ld-linux-x86-64.so.2";
    host_libraries = "host/lib";
    userspace = "guest/usr";
  };
  manifest = builtins.toJSON (
    common
    // {
      schema = 1;
      nvidia_driver = "0.0.0";
      qemu_data = "share/qemu";
      backend = "libexec/vhost-user-nvgpu";
      virtiofsd = "libexec/virtiofsd";
      modules = map modulePath nvidiaModules;
      workload_config = "guest/workload.json";
      host_driver_libraries = true;
      amdgpu = common // {
        modules = map modulePath amdModules;
      };
    }
  );
  workload = builtins.toJSON {
    schema = 1;
    width = 1920;
    height = 1080;
    warmup_ms = 200;
    sample_ms = 1000;
    cases = [
      {
        name = "render";
        mode = "gpu";
        kernel = "integer";
        workers = 0;
        working_set_kib = 512;
        work_units = 1;
        gpu_iterations = 1;
      }
    ];
  };
in
stdenv.mkDerivation {
  pname = "legion-kvm";
  inherit (legionSource) version;
  dontUnpack = true;
  # guest/usr is a Debian tree: patchelf, strip and patchShebangs would point
  # it at /nix/store, which the guest does not have.
  dontFixup = true;
  passAsFile = [
    "manifest"
    "workload"
  ];
  inherit manifest workload;
  installPhase = ''
    runHook preInstall
    install -Dm0755 ${rust.static}/bin/legion $out/bin/legion
    # The launcher dispatches on argv[0]; hardlinks keep the tool names.
    for name in legion-qemu legion-amdgpu-qemu legion-backend legion-virtiofsd; do
      ln $out/bin/legion $out/bin/$name
    done
    install -Dm0755 ${qemu}/bin/qemu-system-x86_64 $out/libexec/qemu-system-x86_64
    install -Dm0755 ${rust.vhost-user-nvgpu}/bin/vhost-user-nvgpu $out/libexec/vhost-user-nvgpu
    install -Dm0755 ${virtiofsd}/bin/virtiofsd $out/libexec/virtiofsd
    install -Dm0755 ${glibc}/lib/ld-linux-x86-64.so.2 $out/host/lib/ld-linux-x86-64.so.2
    mkdir -p $out/share
    cp -r ${qemu}/share/qemu $out/share/qemu

    install -Dm0644 ${kernel}/bzImage $out/guest/kernel
    install -Dm0644 ${kernel}/config $out/guest/kernel.config
    install -Dm0755 ${rust.static}/bin/legion-guest-probe $out/guest/init
    ${lib.concatMapStrings (name: ''
      install -Dm0644 ${kernel}/modules/${name}.ko $out/${modulePath name}
    '') modules}
    cp -a ${guest}/usr $out/guest/usr
    install -m0644 $workloadPath $out/guest/workload.json
    install -m0644 $manifestPath $out/runtime.json
    install -m0644 ${legionSource.src}/README.md $out/README.txt
    runHook postInstall
  '';

  passthru = {
    inherit
      proton
      rust
      kernel
      qemu
      wine
      guest
      ;
  };

  meta = {
    description = "Runs Windows applications through Proton inside a Linux KVM guest";
    homepage = "https://github.com/brcly/legion-kvm";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "legion";
  };
}
