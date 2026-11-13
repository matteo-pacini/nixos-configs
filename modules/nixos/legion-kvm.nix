{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.legion-kvm;
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
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users added to the kvm group so they can open /dev/kvm.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    programs.steam.extraCompatPackages = [ cfg.package.proton ];
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "kvm" ];
    });
  };
}
