{
  # Periodic TRIM for SSDs — prevents write amplification degradation
  services.fstrim.enable = true;

  # noatime on root XFS — eliminates unnecessary access-time writes
  fileSystems."/".options = [ "noatime" ];

  # Noop scheduler for SSDs — bypass kernel I/O scheduling overhead
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
  '';

  # VM subsystem tuning for a storage server
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };

  # Nix build parallelism — dual Xeon E5-2697 v4 (36C/72T)
  nix.settings = {
    max-jobs = 8;
    cores = 8;
  };
}
