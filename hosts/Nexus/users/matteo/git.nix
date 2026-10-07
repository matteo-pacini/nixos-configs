{ ... }:
{
  custom.git = {
    enable = true;
    signing = {
      enable = true;
      allowedSignersContent = ''
        * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5baw4ttSTVa2+SdBJO59KXQI8Gnhkf4PLhbq/vo0Ws
      '';
    };
  };

  custom.ssh = {
    enable = true;
    mesh.enable = true;
    mesh.host = "Nexus";
    extraSettings."fpnas" = {
      HostName = "fpnas3.tailadca8a.ts.net";
      User = "fabrizio";
      Port = "2812";
    };
  };
}
