{ pkgs, lib, ... }:
{
  systemd.tmpfiles.rules = [
    "d /diskpool/paperless 2770 paperless paperless"
    "d /diskpool/paperless-export 0750 paperless paperless"
  ];

  # POSIX default ACLs on the paperless media directory.
  # Grants the nextcloud user read+execute access to all files created by
  # paperless, regardless of paperless's strict 0066 umask.
  systemd.services.paperless-acl-setup = {
    description = "Set POSIX ACLs on paperless media directory for Nextcloud access";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [
      "paperless-scheduler.service"
      "phpfpm-nextcloud.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart =
        let
          script = pkgs.writeShellScript "paperless-acl-setup" ''
            set -euo pipefail
            MEDIA_DIR="/diskpool/paperless"
            # Grant read on existing files, execute on directories
            ${lib.getExe' pkgs.acl "setfacl"} -R -m u:nextcloud:rX "$MEDIA_DIR"
            # Set default ACL so new files auto-inherit
            ${lib.getExe' pkgs.acl "setfacl"} -R -d -m u:nextcloud:rX "$MEDIA_DIR"
          '';
        in
        "${script}";
    };
  };

  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = 28981;
    # Sets PAPERLESS_URL, without which Django rejects the login POST's CSRF
    # origin when reached through Caddy. configureNginx stays off.
    domain = "docs.matteopacini.me";
    mediaDir = "/diskpool/paperless";

    # Nightly document_exporter (default 01:30, before the 03:00 backup job).
    # The unit stops the paperless services while it runs and starts them
    # again afterwards, so never run it from inside backup-job. Kept off the
    # default /var/lib/paperless/export, which would copy media onto the root SSD.
    exporter = {
      enable = true;
      directory = "/diskpool/paperless-export";
    };

    # Database configuration
    database.createLocally = true;

    # Consumption directory is public for easy document uploads
    consumptionDirIsPublic = true;

    # OCR and other settings
    settings = {
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];
      PAPERLESS_OCR_LANGUAGE = "ita+eng";
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };
    };
  };
}
