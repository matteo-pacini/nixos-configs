# Auto-generated using compose2nix v0.3.1.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman+".allowedUDPPorts = [ 53 ];

  virtualisation.oci-containers.backend = "podman";

  # Containers
  virtualisation.oci-containers.containers."nexus-n8n-n8n" = {
    image = "docker.n8n.io/n8nio/n8n:1.97.1";
    environment = {
      "DB_POSTGRESDB_DATABASE" = "n8n";
      "DB_POSTGRESDB_HOST" = "postgres";
      "DB_POSTGRESDB_PASSWORD" = "password";
      "DB_POSTGRESDB_PORT" = "5432";
      "DB_POSTGRESDB_USER" = "user";
      "DB_TYPE" = "postgresdb";
      "GENERIC_TIMEZONE" = "Europe/London";
      "N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE" = "true";
      "N8N_HOST" = "n8n.matteopacini.me";
      "N8N_PORT" = "5678";
      "N8N_PROTOCOL" = "http";
      "N8N_SECURE_COOKIE" = "false";
      "NODE_ENV" = "production";
      "NODE_FUNCTION_ALLOW_BUILTIN" = "*";
      "NODE_FUNCTION_ALLOW_EXTERNAL" = "*";
      "TZ" = "Europe/London";
      "WEBHOOK_URL" = "https://n8n.matteopacini.me";
    };
    volumes = [
      "nexus-n8n_n8n_storage:/home/node/.n8n:rw"
    ];
    ports = [
      "5678:5678/tcp"
    ];
    dependsOn = [
      "nexus-n8n-postgres"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=n8n"
      "--network=nexus-n8n_default"
    ];
  };
  systemd.services."podman-nexus-n8n-n8n" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-nexus-n8n_default.service"
      "podman-volume-nexus-n8n_n8n_storage.service"
    ];
    requires = [
      "podman-network-nexus-n8n_default.service"
      "podman-volume-nexus-n8n_n8n_storage.service"
    ];
    partOf = [
      "podman-compose-nexus-n8n-root.target"
    ];
    wantedBy = [
      "podman-compose-nexus-n8n-root.target"
    ];
  };
  virtualisation.oci-containers.containers."nexus-n8n-postgres" = {
    image = "postgres:16.9";
    environment = {
      "POSTGRES_DB" = "n8n";
      "POSTGRES_PASSWORD" = "password";
      "POSTGRES_USER" = "user";
    };
    volumes = [
      "nexus-n8n_db_storage:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=pg_isready -h localhost -U user -d n8n"
      "--health-interval=5s"
      "--health-retries=10"
      "--health-timeout=5s"
      "--network-alias=postgres"
      "--network=nexus-n8n_default"
    ];
  };
  systemd.services."podman-nexus-n8n-postgres" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-nexus-n8n_default.service"
      "podman-volume-nexus-n8n_db_storage.service"
    ];
    requires = [
      "podman-network-nexus-n8n_default.service"
      "podman-volume-nexus-n8n_db_storage.service"
    ];
    partOf = [
      "podman-compose-nexus-n8n-root.target"
    ];
    wantedBy = [
      "podman-compose-nexus-n8n-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-nexus-n8n_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f nexus-n8n_default";
    };
    script = ''
      podman network inspect nexus-n8n_default || podman network create nexus-n8n_default
    '';
    partOf = [ "podman-compose-nexus-n8n-root.target" ];
    wantedBy = [ "podman-compose-nexus-n8n-root.target" ];
  };

  # Volumes
  systemd.services."podman-volume-nexus-n8n_db_storage" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect nexus-n8n_db_storage || podman volume create nexus-n8n_db_storage
    '';
    partOf = [ "podman-compose-nexus-n8n-root.target" ];
    wantedBy = [ "podman-compose-nexus-n8n-root.target" ];
  };
  systemd.services."podman-volume-nexus-n8n_n8n_storage" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect nexus-n8n_n8n_storage || podman volume create nexus-n8n_n8n_storage
    '';
    partOf = [ "podman-compose-nexus-n8n-root.target" ];
    wantedBy = [ "podman-compose-nexus-n8n-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-nexus-n8n-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
