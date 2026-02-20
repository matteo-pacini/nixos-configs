{ ... }:
{
  custom.git.enable = true;

  custom.ssh = {
    enable = true;
    extraMatchBlocks."fpnas" = {
      extraOptions = {
        HostName = "fpnas3.tailadca8a.ts.net";
        User = "fabrizio";
        Port = "2812";
      };
    };
  };
}
