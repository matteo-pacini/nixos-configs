{ ... }:
{
  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = false; # tailnet + trusted-device rule in ../networking.nix
  };
}
