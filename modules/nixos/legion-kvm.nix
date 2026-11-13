{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.legion-kvm;
  package = cfg.package.override { inherit (cfg) resolution; };
in
{
  options.custom.legion-kvm = {
    enable = lib.mkEnableOption ''
      Legion KVM, which runs Windows games through Proton inside a KVM guest.
      Set a game's Steam launch options to `legion %command%` and its
      compatibility tool to "GE-Proton11-11 (Legion)", the only Proton build
      the runtime's Wine repair recipe accepts'';
    # pkgs.legion-kvm comes from the BrightFalls overlay; another host needs
    # its own callPackage of packages/legion-kvm.
    package = lib.mkPackageOption pkgs "legion-kvm" { };
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
