# What lib/ssh-mesh.nix doesn't say about each of its hosts: the kind of
# device, and whether it runs nix-darwin. Read by the herdr workbench
# (space-cards) and the BrightFalls fleet helper (desk-fleet).
{
  BrightFalls = {
    device = "desktop";
    darwin = false;
  };
  Nexus = {
    device = "server";
    darwin = false;
  };
  CauldronLake = {
    device = "laptop";
    darwin = false;
  };
  NightSprings = {
    device = "laptop";
    darwin = true;
  };
  WorkLaptop = {
    device = "laptop";
    darwin = true;
  };
}
