{
  pkgs,
  lib,
  isVM,
  ...
}:
{
  # Basic virtualization support (no GPU passthrough)

  virtualisation.spiceUSBRedirection.enable = lib.mkIf (!isVM) true;

  users.extraUsers.matteo.extraGroups = lib.mkIf (!isVM) [
    "kvm"
    "libvirtd"
  ];

  programs.virt-manager.enable = lib.mkIf (!isVM) true;

  virtualisation.libvirtd = lib.mkIf (!isVM) {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };
}
