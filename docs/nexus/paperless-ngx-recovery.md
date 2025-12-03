# Paperless-ngx Recovery Handbook

## Quick Reference

| Item | Value |
|------|-------|
| Restic Repository | `s3:s3.eu-central-003.backblazeb2.com/config-nexus-backup` |
| Backup Path | `/diskpool/configuration` |
| PostgreSQL Backup Location | `/diskpool/configuration/postgresql/all.sql.gz` |
| Credentials | `/run/agenix/nexus/restic-env` and `/run/agenix/nexus/restic-password` |

---

## 1. Diagnose the Problem

```bash
# Check if documents table is empty
sudo -u postgres psql paperless -c "SELECT COUNT(*) FROM documents_document;"

# Check users (superuser should exist)
sudo -u postgres psql paperless -c "SELECT username, is_superuser, date_joined FROM auth_user;"
```

---

## 2. List Available Restic Snapshots

```bash
sudo nix-shell -p restic --run "\
  AWS_ACCESS_KEY_ID='<B2_KEY_ID>' \
  AWS_SECRET_ACCESS_KEY='<B2_APP_KEY>' \
  RESTIC_PASSWORD_FILE=/run/agenix/nexus/restic-password \
  RESTIC_REPOSITORY=s3:s3.eu-central-003.backblazeb2.com/config-nexus-backup \
  restic snapshots"
```

Pick a snapshot from **before** the incident date.

---

## 3. Restore PostgreSQL Backup from Restic

```bash
sudo nix-shell -p restic --run "\
  AWS_ACCESS_KEY_ID='<B2_KEY_ID>' \
  AWS_SECRET_ACCESS_KEY='<B2_APP_KEY>' \
  RESTIC_PASSWORD_FILE=/run/agenix/nexus/restic-password \
  RESTIC_REPOSITORY=s3:s3.eu-central-003.backblazeb2.com/config-nexus-backup \
  restic restore <SNAPSHOT_ID> \
    --target /tmp/restore \
    --include /diskpool/configuration/postgresql"
```

---

## 4. Stop Paperless Services

```bash
sudo systemctl stop \
  paperless-consumer.service \
  paperless-scheduler.service \
  paperless-task-queue.service \
  paperless-web.service
```

---

## 5. Restore the Database

```bash
# Drop and recreate
sudo -u postgres psql -c "DROP DATABASE paperless;"
sudo -u postgres psql -c "CREATE DATABASE paperless OWNER paperless;"

# Restore from backup
sudo zcat /tmp/restore/diskpool/configuration/postgresql/all.sql.gz \
  | sudo -u postgres psql paperless
```

---

## 6. Verify & Restart

```bash
# Verify documents restored
sudo -u postgres psql paperless -c "SELECT COUNT(*) FROM documents_document;"

# Restart services
sudo systemctl start \
  paperless-consumer.service \
  paperless-scheduler.service \
  paperless-task-queue.service \
  paperless-web.service
```

---

## 7. Cleanup

```bash
sudo rm -rf /tmp/restore
```

---

## Notes

- Backups run **daily** via `services.restic.backups.config`
- PostgreSQL dumps are created by `services.postgresqlBackup`
- Media files are at `/diskpool/configuration/paperless/documents/` (usually intact)
- Restic credentials are managed by **agenix**

