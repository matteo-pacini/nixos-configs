{ pkgs, config, ... }:
let
  dataDir = config.services.radarr.dataDir;

  migrateRadarrToPostgres = pkgs.writeShellScriptBin "migrate-radarr-to-postgres" ''
    set -euo pipefail

    RADARR_DB="${dataDir}/radarr.db"

    echo "=== Radarr SQLite to PostgreSQL Migration ==="
    echo ""

    # Check if service is running - abort if so
    if systemctl is-active --quiet radarr; then
      echo "ERROR: Radarr service is running. Please stop it first:"
      echo "  sudo systemctl stop radarr"
      exit 1
    fi

    # Check if SQLite database exists
    if [[ ! -f "$RADARR_DB" ]]; then
      echo "ERROR: SQLite database not found at $RADARR_DB"
      exit 1
    fi

    echo "Step 1: Clearing default data from PostgreSQL tables..."
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "QualityProfiles";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "QualityDefinitions";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "DelayProfiles";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "Metadata";'

    echo "Step 2: Migrating data with pgloader..."
    # Clean up pgloader temp directory to avoid permission issues
    rm -rf /tmp/pgloader
    sudo -u radarr ${pkgs.pgloader}/bin/pgloader \
      --with "quote identifiers" \
      --with "data only" \
      --with "reset no sequences" \
      "$RADARR_DB" \
      "postgresql:///radarr-main?host=/run/postgresql"

    echo "Step 3: Resetting PostgreSQL sequences..."
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."MovieFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "MovieFiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."AlternativeTitles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "AlternativeTitles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Blocklist_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Blocklist"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Collections_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Collections"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Commands_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Commands"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Config_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Config"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Credits_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Credits"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."CustomFilters_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "CustomFilters"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."CustomFormats_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "CustomFormats"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."DelayProfiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DelayProfiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."DownloadClientStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadClientStatus"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."DownloadClients_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadClients"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."DownloadHistory_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadHistory"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."ExtraFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ExtraFiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."History_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "History"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."ImportExclusions_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ImportExclusions"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."ImportListMovies_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ImportListMovies"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."IndexerStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "IndexerStatus"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Indexers_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Indexers"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."MetadataFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "MetadataFiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Metadata_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Metadata"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."MovieMetadata_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "MovieMetadata"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."MovieTranslations_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "MovieTranslations"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Movies_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Movies"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."NamingConfig_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "NamingConfig"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Notifications_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Notifications"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."PendingReleases_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "PendingReleases"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."QualityProfiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "QualityProfiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."QualityDefinitions_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "QualityDefinitions"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."ReleaseProfiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ReleaseProfiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."RootFolders_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "RootFolders"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."ScheduledTasks_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ScheduledTasks"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."SubtitleFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "SubtitleFiles"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Tags_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Tags"));'
    sudo -u postgres psql -d "radarr-main" -c 'SELECT setval('"'"'public."Users_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Users"));'

    echo ""
    echo "=== Migration Complete ==="
    echo ""
    echo "Make sure your config.xml contains these PostgreSQL settings:"
    echo ""
    echo "  <PostgresUser>radarr</PostgresUser>"
    echo "  <PostgresHost>/run/postgresql</PostgresHost>"
    echo "  <PostgresPort>5432</PostgresPort>"
    echo "  <PostgresMainDb>radarr-main</PostgresMainDb>"
    echo "  <PostgresLogDb>radarr-log</PostgresLogDb>"
    echo ""
    echo "You can now start Radarr and verify it works:"
    echo "  sudo systemctl start radarr"
    echo ""
    echo "If everything works, you can optionally remove the old SQLite database:"
    echo "  rm ${dataDir}/radarr.db"
    echo "  rm ${dataDir}/logs.db"
  '';
in
{
  environment.systemPackages = [ migrateRadarrToPostgres ];

  users.users."radarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true; # Direct port access (7878)
  };

  # Radarr requires PostgreSQL to be running
  systemd.services.radarr = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
}
