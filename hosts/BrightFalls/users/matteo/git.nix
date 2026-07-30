_:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
    signing = {
      enable = true;
      allowedSignersContent = ''
        * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPE5KKe9sITI9nOEb744SGLZg4Jw7G0+1uWzXhvwj700
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
