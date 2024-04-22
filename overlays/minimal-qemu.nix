final: prev: {
  qemu = prev.qemu.override {
    hostCpuTargets = ["x86_64-softmmu"];
  };
}
