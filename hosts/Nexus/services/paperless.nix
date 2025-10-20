{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /diskpool/paperless 2770 paperless paperless"
  ];

  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = 28981;
    mediaDir = "/diskpool/paperless";

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
