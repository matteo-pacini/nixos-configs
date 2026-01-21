{ pkgs, config, ... }:
let
  dataDir = config.services.sonarr.dataDir;

  migrateSonarrToPostgres = pkgs.writeShellScriptBin "migrate-sonarr-to-postgres" ''
    set -euo pipefail

    SONARR_DB="${dataDir}/sonarr.db"

    echo "=== Sonarr SQLite to PostgreSQL Migration ==="
    echo ""

    # Check if service is running - abort if so
    if systemctl is-active --quiet sonarr; then
      echo "ERROR: Sonarr service is running. Please stop it first:"
      echo "  sudo systemctl stop sonarr"
      exit 1
    fi

    # Check if SQLite database exists
    if [[ ! -f "$SONARR_DB" ]]; then
      echo "ERROR: SQLite database not found at $SONARR_DB"
      exit 1
    fi

    echo "Step 1: Clearing default data from PostgreSQL tables..."
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "QualityProfiles";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "QualityDefinitions";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "DelayProfiles";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "Metadata";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "Config";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "VersionInfo";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "ScheduledTasks";'

    echo "Step 2: Migrating data with pgloader..."
    # Clean up pgloader temp directory to avoid permission issues
    rm -rf /tmp/pgloader
    sudo -u sonarr ${pkgs.pgloader}/bin/pgloader \
      --with "quote identifiers" \
      --with "data only" \
      --with "reset no sequences" \
      "$SONARR_DB" \
      "postgresql:///sonarr-main?host=/run/postgresql"

    echo "Step 3: Resetting PostgreSQL sequences..."
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."AutoTagging_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "AutoTagging"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Blocklist_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Blocklist"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Commands_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Commands"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Config_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Config"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."CustomFilters_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "CustomFilters"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."CustomFormats_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "CustomFormats"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."DelayProfiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DelayProfiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."DownloadClientStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadClientStatus"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."DownloadClients_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadClients"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."DownloadHistory_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "DownloadHistory"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."EpisodeFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "EpisodeFiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Episodes_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Episodes"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."ExtraFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ExtraFiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."History_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "History"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."ImportListExclusions_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ImportListExclusions"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."ImportListStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ImportListStatus"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."ImportLists_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ImportLists"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."IndexerStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "IndexerStatus"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Indexers_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Indexers"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."MetadataFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "MetadataFiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Metadata_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Metadata"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."NamingConfig_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "NamingConfig"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."NotificationStatus_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "NotificationStatus"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Notifications_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Notifications"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."PendingReleases_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "PendingReleases"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."QualityDefinitions_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "QualityDefinitions"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."QualityProfiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "QualityProfiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."RemotePathMappings_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "RemotePathMappings"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."RootFolders_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "RootFolders"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."SceneMappings_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "SceneMappings"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."ScheduledTasks_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "ScheduledTasks"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Series_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Series"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."SubtitleFiles_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "SubtitleFiles"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Tags_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Tags"));'
    sudo -u postgres psql -d "sonarr-main" -c 'SELECT setval('"'"'public."Users_Id_seq"'"'"', (SELECT COALESCE(MAX("Id"), 1) FROM "Users"));'

    echo ""
    echo "=== Migration Complete ==="
    echo ""
    echo "Make sure your config.xml contains these PostgreSQL settings:"
    echo ""
    echo "  <PostgresUser>sonarr</PostgresUser>"
    echo "  <PostgresHost>/run/postgresql</PostgresHost>"
    echo "  <PostgresPort>5432</PostgresPort>"
    echo "  <PostgresMainDb>sonarr-main</PostgresMainDb>"
    echo "  <PostgresLogDb>sonarr-log</PostgresLogDb>"
    echo ""
    echo "You can now start Sonarr and verify it works:"
    echo "  sudo systemctl start sonarr"
    echo ""
    echo "If everything works, you can optionally remove the old SQLite database:"
    echo "  rm ${dataDir}/sonarr.db"
    echo "  rm ${dataDir}/logs.db"
  '';
in
{
  environment.systemPackages = [ migrateSonarrToPostgres ];

  users.users."sonarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = true; # Direct port access (8989)
  };

  # Sonarr requires PostgreSQL to be running
  systemd.services.sonarr = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    serviceConfig = {
      # Allow changing ownership of imported files from download clients
      AmbientCapabilities = [ "CAP_CHOWN" "CAP_FOWNER" ];
      CapabilityBoundingSet = [ "CAP_CHOWN" "CAP_FOWNER" ];
    };
  };
}
