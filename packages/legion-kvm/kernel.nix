# Guest kernel and modules, built by upstream's kernel/build_guest.py so its
# config policy checks still run.
{
  stdenv,
  fetchurl,
  python3,
  bison,
  flex,
  bc,
  perl,
  elfutils,
  openssl,
  legionSource,
}:
stdenv.mkDerivation {
  pname = "legion-kvm-guest-kernel";
  version = "6.18.62";
  # Hash from upstream's config/sources.json.
  src = fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.62.tar.xz";
    sha256 = "490a7aedf1b355c565d3a6c05333ccccb5da82064eca46b590448a7099d7d651";
  };
  nativeBuildInputs = [
    python3
    bison
    flex
    bc
    perl
    elfutils
    openssl
  ];
  hardeningDisable = [ "all" ];
  dontConfigure = true;
  enableParallelBuilding = true;
  buildPhase = ''
    runHook preBuild
    patchShebangs scripts
    cp -r ${legionSource.src}/kernel ../kernel
    chmod -R u+w ../kernel
    jobs=$(( NIX_BUILD_CORES > 16 ? 16 : NIX_BUILD_CORES ))
    python3 ../kernel/build_guest.py --source . --output ../out --native-display --jobs $jobs \
      || { tail -50 ../out/build.log; exit 1; }
    for name in nvidia:backends/nvidia/driver cpuid:guest-cpuid; do
      cp -r ${legionSource.src}/''${name#*:} ../modules-''${name%%:*}
      chmod -R u+w ../modules-''${name%%:*}
      make -C ../out M=$PWD/../modules-''${name%%:*} CONFIG_VIRTIO_GPU_NV=m -j$jobs modules
    done
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 ../out/arch/x86/boot/bzImage $out/bzImage
    install -Dm0644 ../out/.config $out/config
    for ko in drivers/misc/ntsync.ko drivers/virtio/virtio_dma_buf.ko drivers/gpu/drm/drm_shmem_helper.ko \
              drivers/gpu/drm/drm_kms_helper.ko drivers/gpu/drm/virtio/virtio-gpu.ko; do
      install -Dm0644 ../out/$ko $out/modules/$(basename $ko)
    done
    install -Dm0644 ../modules-nvidia/virtio_gpu_nv.ko $out/modules/virtio_gpu_nv.ko
    install -Dm0644 ../modules-cpuid/legion_cpuid.ko $out/modules/legion_cpuid.ko
    runHook postInstall
  '';
}
