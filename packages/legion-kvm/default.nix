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
  virglrenderer,
  mesa,
  # Guest display mode for games. Upstream accepts up to 3840x2160.
  resolution ? {
    width = 1920;
    height = 1080;
  },
  # Refresh rate in Hz that the guest display's EDID advertises; 75 is QEMU's
  # own value.
  refreshRate ? 75,
  # Default guest memory in MiB (upstream: 12288); LEGION_MEMORY_MIB overrides.
  memoryMiB ? 12288,
  # Open the game window fullscreen unless LEGION_FULLSCREEN is set
  # to something other than 1 (upstream: windowed unless it is 1).
  fullscreen ? false,
  # Pin each vCPU to the host CPU at the same position in the topology the
  # guest is given, so guest SMT siblings are host siblings.
  pinVcpus ? false,
  # Build upstream's optional Wine ntdll repair. A session uses it only with
  # LEGION_WINE_REPAIR=1, and only with a Proton whose ntdll matches
  # upstream's config/compatibility.json.
  wineRepair ? false,
}:
assert resolution.width >= 64 && resolution.width <= 3840;
assert resolution.height >= 64 && resolution.height <= 2160;
assert refreshRate >= 30 && refreshRate <= 240;
# The launcher's own accepted range for LEGION_MEMORY_MIB.
assert memoryMiB >= 4096 && memoryMiB <= 65536;
let
  legionSource = callPackage ./source.nix { };
  proton = callPackage ./proton.nix { };
  rust = callPackage ./rust.nix {
    inherit
      legionSource
      resolution
      memoryMiB
      fullscreen
      pinVcpus
      wineRepair
      ;
  };
  wine = if wineRepair then callPackage ./wine.nix { inherit legionSource proton; } else null;
  kernel = callPackage ./kernel.nix { inherit legionSource; };
  virgl = callPackage ./virglrenderer.nix { inherit virglrenderer legionSource; };
  qemu = callPackage ./qemu.nix {
    inherit legionSource refreshRate;
    virglrenderer = virgl;
  };
  guest = callPackage ./guest.nix {
    inherit
      vmTools
      legionSource
      rust
      proton
      wine
      ;
  };

  # Module order and numbering follow build_runtime.py assemble().
  modules = [
    "virtio_dma_buf"
    "drm_shmem_helper"
    "drm_kms_helper"
    "virtio-gpu"
    "legion_cpuid"
    "ntsync"
  ];
  modulePath =
    name:
    "guest/modules/${lib.fixedWidthNumber 3 (lib.lists.findFirstIndex (m: m == name) null modules)}.ko";

  manifest = builtins.toJSON {
    schema = 2;
    qemu = "libexec/qemu-system-x86_64";
    qemu_data = "share/qemu";
    renderer = "libexec/virgl_render_server";
    virtiofsd = "libexec/virtiofsd";
    # Every asset must resolve inside the runtime root, so the loader is a
    # copy. host/lib stays otherwise empty: the Nix-built tools carry RUNPATHs.
    host_loader = "host/lib/ld-linux-x86-64.so.2";
    host_libraries = "host/lib";
    kernel = "guest/kernel";
    init = "guest/init";
    modules = map modulePath modules;
    userspace = "guest/usr";
    workload_config = "guest/workload.json";
  };
  build = builtins.toJSON {
    build_id = legionSource.src.rev;
    toolchain_image = "";
    optional_wine_repair = wineRepair;
  };
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
    "build"
    "workload"
  ];
  inherit manifest build workload;
  installPhase = ''
    runHook preInstall
    install -Dm0755 ${rust.static}/bin/legion $out/bin/legion
    # The launcher dispatches on argv[0]; hardlinks keep the tool names.
    for name in legion-qemu legion-render-server legion-virtiofsd; do
      ln $out/bin/legion $out/bin/$name
    done
    install -Dm0755 ${qemu}/bin/qemu-system-x86_64 $out/libexec/qemu-system-x86_64
    install -Dm0755 ${virgl}/libexec/virgl_render_server $out/libexec/virgl_render_server
    install -Dm0755 ${virtiofsd}/bin/virtiofsd $out/libexec/virtiofsd
    install -Dm0755 ${glibc}/lib/ld-linux-x86-64.so.2 $out/host/lib/ld-linux-x86-64.so.2
    # The render server loads only this layer (VK_LAYER_PATH=host/vulkan) to
    # pick the GPU; the Vulkan driver itself is the host's.
    install -Dm0644 ${mesa}/share/vulkan/implicit_layer.d/VkLayer_MESA_device_select.json \
      $out/host/vulkan/VkLayer_MESA_device_select.json
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
    install -m0644 $buildPath $out/build.json
    install -m0644 ${legionSource.src}/README.md $out/README.txt
    runHook postInstall
  '';

  passthru = {
    inherit
      proton
      rust
      kernel
      virgl
      qemu
      guest
      wine
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
