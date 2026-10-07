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
    mesh.enable = true;
    mesh.host = "NightSprings";
    brightfalls.initrd = true;
    github.enable = true;
    extraSettings."fpnas" = {
      HostName = "fpnas3.tailadca8a.ts.net";
      User = "fabrizio";
      Port = "2812";
    };
  };
}
