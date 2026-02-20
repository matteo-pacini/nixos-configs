{ ... }:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
    signing = {
      enable = true;
      allowedSignersContent = ''
        * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDrJTfkpn4k43/HcSuhM71ciHXAwjMphCxZXRR3zLhPG
      '';
    };
    includes = [
      {
        contents = {
          user = {
            email = "matteo.pacini@transreport.co.uk";
          };
        };
        condition = "gitdir:/Users/matteo/Work/";
      }
    ];
  };

  custom.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    nexus.enable = true;
    nexus.tailscaleAliases = true;
    brightfalls.enable = true;
    brightfalls.tailscaleAliases = true;
    github.enable = true;
    extraMatchBlocks."fpnas" = {
      extraOptions = {
        HostName = "fpnas3.tailadca8a.ts.net";
        User = "fabrizio";
        Port = "2812";
      };
    };
  };
}
