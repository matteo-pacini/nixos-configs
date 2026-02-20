{ ... }:
{
  imports = [
    ./docker-compose.nix
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/n8n 0750 1000 1000 -"
    "d /var/lib/postgresql_n8n 0750 999 999 -"
  ];
}
