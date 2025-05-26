{
  pkgs,
  ...
}:
{
  imports = [
    ./docker-compose.nix
  ];

  systemd.tmpfiles.rules = [
    "d /diskpool/limbo 2777 root users"
  ];

  systemd.services.n8n-post-start = {
    description = "Execute commands in n8n container after startup";
    after = [ "podman-nexus-n8n-n8n.service" ];
    requires = [ "podman-nexus-n8n-n8n.service" ];
    partOf = [ "podman-compose-nexus-n8n-root.target" ];
    wantedBy = [ "podman-compose-nexus-n8n-root.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.podman}/bin/podman exec -u root nexus-n8n-n8n sh -c "apk add --no-cache ffmpeg"
      echo "FFmpeg installation completed"
    '';
  };
}
