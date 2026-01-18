# Radarr & Sonarr PostgreSQL Migration Handbook

## Quick Reference

| Item | Radarr | Sonarr |
|------|--------|--------|
| Main Database | `radarr-main` | `sonarr-main` |
| Log Database | `radarr-log` | `sonarr-log` |
| PostgreSQL User | `radarr` | `sonarr` |
| Data Directory | `/var/lib/radarr/.config/Radarr` | `/var/lib/sonarr/.config/NzbDrone` |
| Config File | `config.xml` | `config.xml` |
| SQLite Database | `radarr.db` | `sonarr.db` |
| Service Port | 7878 | 8989 |
| Migration Script | `migrate-radarr-to-postgres` | `migrate-sonarr-to-postgres` |

---

## Prerequisites

Before starting the migration:

1. **Deploy the updated NixOS configuration** containing the new PostgreSQL databases and migration scripts
2. **Run the database ownership setup script** (one-time):
   ```bash
   sudo setup-arr-databases
   ```
3. **Verify databases exist**:
   ```bash
   sudo -u postgres psql -c '\l'
   ```
   You should see `radarr-main`, `radarr-log`, `sonarr-main`, `sonarr-log` in the list.

---

## Migration Procedure

> ⚠️ **Important**: Migrate one service at a time. Complete Radarr before starting Sonarr (or vice versa).

### Radarr Migration

#### Step 1: Stop Radarr

```bash
sudo systemctl stop radarr
```

#### Step 2: Backup config.xml

```bash
sudo cp /var/lib/radarr/.config/Radarr/config.xml \
       /var/lib/radarr/.config/Radarr/config.xml.bak
```

#### Step 3: Edit config.xml

Add the following PostgreSQL settings before the closing `</Config>` tag:

```xml
<PostgresUser>radarr</PostgresUser>
<PostgresHost>/run/postgresql</PostgresHost>
<PostgresPort>5432</PostgresPort>
<PostgresMainDb>radarr-main</PostgresMainDb>
<PostgresLogDb>radarr-log</PostgresLogDb>
```

#### Step 4: Initialize PostgreSQL Schema

Start Radarr once to create the database schema:

```bash
sudo systemctl start radarr
```

Wait ~30 seconds for Radarr to initialize the tables, then stop it:

```bash
sudo systemctl stop radarr
```

#### Step 5: Run Migration Script

```bash
sudo migrate-radarr-to-postgres
```

The script will:
- Verify Radarr is stopped
- Clear default data from PostgreSQL tables
- Migrate data from SQLite using pgloader

#### Step 6: Start and Verify

```bash
sudo systemctl start radarr
```

Open http://nexus.home.internal:7878 and verify:
- Movies are present
- Quality profiles are intact
- Download clients are configured

---

### Sonarr Migration

#### Step 1: Stop Sonarr

```bash
sudo systemctl stop sonarr
```

#### Step 2: Backup config.xml

```bash
sudo cp /var/lib/sonarr/.config/NzbDrone/config.xml \
       /var/lib/sonarr/.config/NzbDrone/config.xml.bak
```

#### Step 3: Edit config.xml

Add the following PostgreSQL settings before the closing `</Config>` tag:

```xml
<PostgresUser>sonarr</PostgresUser>
<PostgresHost>/run/postgresql</PostgresHost>
<PostgresPort>5432</PostgresPort>
<PostgresMainDb>sonarr-main</PostgresMainDb>
<PostgresLogDb>sonarr-log</PostgresLogDb>
```

#### Step 4: Initialize PostgreSQL Schema

Start Sonarr once to create the database schema:

```bash
sudo systemctl start sonarr
```

Wait ~30 seconds for Sonarr to initialize the tables, then stop it:

```bash
sudo systemctl stop sonarr
```

#### Step 5: Run Migration Script

```bash
sudo migrate-sonarr-to-postgres
```

The script will:
- Verify Sonarr is stopped
- Clear default data from PostgreSQL tables (more tables than Radarr)
- Migrate data from SQLite using pgloader

#### Step 6: Start and Verify

```bash
sudo systemctl start sonarr
```

Open http://nexus.home.internal:8989 and verify:
- Series are present
- Quality profiles are intact
- Download clients are configured

---

## Cleanup (After Successful Migration)

Once you've verified both services work correctly with PostgreSQL:

### Remove SQLite Databases

```bash
# Radarr
sudo rm /var/lib/radarr/.config/Radarr/radarr.db
sudo rm /var/lib/radarr/.config/Radarr/radarr.db-shm
sudo rm /var/lib/radarr/.config/Radarr/radarr.db-wal
sudo rm /var/lib/radarr/.config/Radarr/logs.db

# Sonarr
sudo rm /var/lib/sonarr/.config/NzbDrone/sonarr.db
sudo rm /var/lib/sonarr/.config/NzbDrone/sonarr.db-shm
sudo rm /var/lib/sonarr/.config/NzbDrone/sonarr.db-wal
sudo rm /var/lib/sonarr/.config/NzbDrone/logs.db
```

### Remove config.xml Backups (Optional)

```bash
sudo rm /var/lib/radarr/.config/Radarr/config.xml.bak
sudo rm /var/lib/sonarr/.config/NzbDrone/config.xml.bak
```

---

## Troubleshooting

### Migration script fails with "service is running"

```bash
sudo systemctl stop radarr  # or sonarr
sudo migrate-radarr-to-postgres  # or migrate-sonarr-to-postgres
```

### Migration script fails with "SQLite database not found"

Verify the database exists:

```bash
sudo ls -la /var/lib/radarr/.config/Radarr/radarr.db
sudo ls -la /var/lib/sonarr/.config/NzbDrone/sonarr.db
```

### PostgreSQL tables don't exist (DELETE fails)

You need to start the service once to initialize the schema:

```bash
sudo systemctl start radarr  # Creates tables
sleep 30
sudo systemctl stop radarr
sudo migrate-radarr-to-postgres
```

### pgloader fails with permission errors

Ensure the PostgreSQL user owns the databases:

```bash
sudo setup-arr-databases
```

### Service fails to start after migration

Check the service logs:

```bash
sudo journalctl -u radarr -f
sudo journalctl -u sonarr -f
```

Common issues:
- Missing PostgreSQL settings in config.xml
- Database ownership not set (run `sudo setup-arr-databases`)

### Duplicate key constraint errors after migration

If you get errors like `duplicate key value violates unique constraint "PK_Episodes"` when adding new content, the PostgreSQL sequences weren't reset correctly during migration.

Reset all sequences for the affected database:

```bash
# For Sonarr
sudo -u postgres psql -d "sonarr-main" -c "
SELECT 'SELECT setval(pg_get_serial_sequence(''\"' || table_name || '\"'', ''Id''), COALESCE((SELECT MAX(\"Id\") FROM \"' || table_name || '\"), 1));'
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" -t | sudo -u postgres psql -d "sonarr-main"

# For Radarr
sudo -u postgres psql -d "radarr-main" -c "
SELECT 'SELECT setval(pg_get_serial_sequence(''\"' || table_name || '\"'', ''Id''), COALESCE((SELECT MAX(\"Id\") FROM \"' || table_name || '\"), 1));'
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" -t | sudo -u postgres psql -d "radarr-main"
```

### Rollback to SQLite

If migration fails, restore from backup:

```bash
sudo systemctl stop radarr
sudo cp /var/lib/radarr/.config/Radarr/config.xml.bak \
       /var/lib/radarr/.config/Radarr/config.xml
sudo systemctl start radarr
```

---

## NixOS Configuration Files

| File | Purpose |
|------|---------|
| `hosts/nexus/services/postgresql.nix` | Database/user creation, `setup-arr-databases` script |
| `hosts/nexus/services/radarr.nix` | Radarr service config, `migrate-radarr-to-postgres` script |
| `hosts/nexus/services/sonarr.nix` | Sonarr service config, `migrate-sonarr-to-postgres` script |

---

## References

- [Radarr PostgreSQL Setup Guide](https://wiki.servarr.com/radarr/postgres-setup)
- [Sonarr PostgreSQL Setup Guide](https://wiki.servarr.com/sonarr/postgres-setup)

---

## Notes

- PostgreSQL databases are backed up daily via `services.postgresqlBackup`
- Backup location: `/var/backup/postgresql/`
- The migration uses Unix socket authentication (no password required)
- pgloader is used with `--with "quote identifiers" --with "data only"` flags

