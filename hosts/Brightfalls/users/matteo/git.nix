_:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
    signing = {
      enable = true;
      allowedSignersContent = ''
        * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtI1woCI1+svEObVH/zT+fp0R11loXEhEBYyuNtBJzN
      '';
    };
  };

  custom.ssh = {
    enable = true;
    nexus.enable = true;
    extraSettings."fpnas" = {
      HostName = "fpnas3.tailadca8a.ts.net";
      User = "fabrizio";
      Port = "2812";
    };
  };
}
