{ pkgs, ... }:
{
  # Basic virtualization support (no GPU passthrough)

  virtualisation.spiceUSBRedirection.enable = true;

  users.extraUsers.matteo.extraGroups = [
    "kvm"
    "libvirtd"
  ];

  programs.virt-manager.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
}
