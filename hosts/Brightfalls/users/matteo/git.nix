{
  lib,
  isVM,
  ...
}:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
  };

  custom.ssh = {
    enable = true;
    nexus.enable = !isVM;
    extraMatchBlocks."fpnas" = {
      extraOptions = {
        HostName = "fpnas3.tailadca8a.ts.net";
        User = "fabrizio";
        Port = "2812";
      };
    };
  };
}
