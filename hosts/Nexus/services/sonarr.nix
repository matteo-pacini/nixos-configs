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
    # Sonarr requires more tables to be cleared than Radarr
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "QualityProfiles";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "QualityDefinitions";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "DelayProfiles";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "Metadata";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "Config";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "VersionInfo";'
    sudo -u postgres psql -d "sonarr-main" -c 'DELETE FROM "ScheduledTasks";'

    echo "Step 2: Migrating data with pgloader..."
    ${pkgs.pgloader}/bin/pgloader \
      --with "quote identifiers" \
      --with "data only" \
      "$SONARR_DB" \
      "postgresql:///sonarr-main?host=/run/postgresql"

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
}
