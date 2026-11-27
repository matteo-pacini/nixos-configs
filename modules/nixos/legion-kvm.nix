{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.legion-kvm;
  package = cfg.package.override {
    inherit (cfg)
      resolution
      refreshRate
      memoryMiB
      fullscreen
      pinVcpus
      wineRepair
      ;
  };
in
{
  options.custom.legion-kvm = {
    enable = lib.mkEnableOption ''
      Legion KVM, which runs Windows games through Proton inside a KVM guest.
      Set a game's Steam launch options to `legion %command%`. Any Proton with
      Wine Wayland support works; "GE-Proton11-11 (Legion)" is installed as
      the tested one'';
    # pkgs.legion-kvm comes from the BrightFalls overlay; another host needs
    # its own callPackage of packages/legion-kvm.
    package = lib.mkPackageOption pkgs "legion-kvm" { };
    # A size equal to the desktop needs `fullscreen`, or the window is shrunk
    # to the work area and the guest display follows it.
    resolution = {
      width = lib.mkOption {
        type = lib.types.ints.between 64 3840;
        default = 1920;
        description = "Width of the guest display that games render to.";
      };
      height = lib.mkOption {
        type = lib.types.ints.between 64 2160;
        default = 1080;
        description = "Height of the guest display that games render to.";
      };
    };
    fullscreen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the game window fullscreen by default. Setting LEGION_FULLSCREEN
        to anything but 1 still opens it windowed.
      '';
    };
    memoryMiB = lib.mkOption {
      type = lib.types.ints.between 4096 65536;
      default = 12288;
      description = ''
        Default guest memory in MiB. LEGION_MEMORY_MIB still overrides it. The
        launcher refuses to start unless MemAvailable covers this plus 2048 MiB.
      '';
    };
    pinVcpus = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Pin each vCPU thread to the host CPU at the same place in the CPU
        topology the guest is given, so the guest's SMT siblings are real
        siblings. Other QEMU and host threads are not restricted.
      '';
    };
    refreshRate = lib.mkOption {
      type = lib.types.ints.between 30 240;
      default = 75;
      description = ''
        Refresh rate, in Hz, that the guest display advertises to games.
        Nothing paces frames to it; it matters to games and limiters that
        cap at the display's refresh rate.
      '';
    };
    wineRepair = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build upstream's optional Wine ntdll repair. A launch uses it only
        with LEGION_WINE_REPAIR=1, and only with a Proton whose ntdll matches
        upstream's, such as "GE-Proton11-11 (Legion)".
      '';
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users added to the kvm group so they can open /dev/kvm.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];
    programs.steam.extraCompatPackages = [ package.proton ];
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "kvm" ];
    });
  };
}
