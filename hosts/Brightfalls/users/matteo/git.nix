_:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
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
