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
  };
}
