{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [ inputs.open-design.nixosModules.open-design ];

  # The upstream NixOS module assigns systemd.services.open-design.environment.PATH
  # directly, which collides (normal priority) with the base systemd module's
  # default unit PATH on current nixpkgs, so plain eval aborts. Force the
  # module's intended value (its `daemonPathEntries`, verbatim) —
  # /run/current-system/sw/bin carries claude + the usual coreutils, so nothing
  # the daemon spawns loses its tools. Gated on autoStart because upstream only
  # defines the unit under `mkIf cfg.autoStart`; without the guard a false
  # autoStart would synthesise a phantom ExecStart-less unit.
  systemd.services.open-design.environment.PATH = lib.mkIf config.services.open-design.autoStart (
    lib.mkForce (
      lib.concatStringsSep ":" [
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ]
    )
  );

  # The daemon runs as the `open-design` system user (not matteo), so its PATH
  # excludes matteo's Home Manager profile. Put claude on the system profile so
  # the daemon can spawn it; subscription auth is set up out-of-band (one-time
  # `/login` as the open-design user) — see docs/nexus/open-design-handbook.md.
  environment.systemPackages = [ pkgs.claude-code ];

  services.open-design = {
    enable = true;
    autoStart = true;
    port = 7457; # daemon, loopback
    webFrontend = {
      enable = true;
      host = "127.0.0.1"; # bundled Caddy stays loopback; front via services.caddy
      port = 5174;
      # Browser Origin when served via the TLS vhost; without it the daemon's
      # origin check 403s write actions.
      allowedOrigins = [ "https://design.matteopacini.me" ];
    };
  };
}
