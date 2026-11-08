# Paperless-ngx Recovery Handbook

## Quick Reference

| Item | Value |
|------|-------|
| Restic Repository | `s3:s3.eu-central-003.backblazeb2.com/paperless-nexus-backup` (`restic-b2 paperless ...`) |
| Exporter Output | `/diskpool/paperless-export` (`paperless-exporter.service`, nightly 01:30) |
| Rsync Copy | `/diskpool/configuration/paperless/{data,media}` (`backup-job.service`, nightly 03:00) |
| PostgreSQL Backup Location | `/diskpool/configuration/postgresql/all.sql.gz` (in the `config` repo, not `paperless`) |
| Retention | 14 daily, 8 weekly, 24 monthly, 10 yearly |
| Credentials | `/run/agenix/nexus/restic-env` and `/run/agenix/nexus/restic-password` |

Two restore routes:

- **Route A, exporter (preferred):** `document_importer` rebuilds documents, tags, correspondents, custom fields and users from the export manifest. It needs no matching DB dump, but the Paperless version must be the one that wrote the export (or newer, if upstream supports the jump).
- **Route B, DB dump:** restores the whole `paperless` database from `all.sql.gz` and relies on the media files matching it. Use it when the export is missing or broken.

Snapshots taken before the `paperless` repo existed live in the `config` repo under `/diskpool/configuration/paperless` (media only, flat layout) until they age out of that repo's retention.

---

## 1. Diagnose the Problem

```bash
# Check if documents table is empty
sudo -u postgres psql paperless -c "SELECT COUNT(*) FROM documents_document;"

# Check users (superuser should exist)
sudo -u postgres psql paperless -c "SELECT username, is_superuser, date_joined FROM auth_user;"
```

If the live media at `/diskpool/paperless` and the local export at `/diskpool/paperless-export` are intact, skip the restic restore and use the local copy.

---

## 2. List Available Restic Snapshots

```bash
sudo restic-b2 paperless snapshots
```

Pick a snapshot from **before** the incident date.

---

## 3. Stop Paperless Services

```bash
sudo systemctl stop \
  paperless-consumer.service \
  paperless-scheduler.service \
  paperless-task-queue.service \
  paperless-web.service
```

---

## 4a. Route A: Import the Export

```bash
sudo restic-b2 paperless restore <SNAPSHOT_ID> \
  --target /tmp/restore \
  --include /diskpool/paperless-export
sudo chown -R paperless:paperless /tmp/restore
```

`document_importer` expects an empty instance. Drop and recreate the database, move the old media directory aside, then let Paperless run its migrations:

```bash
sudo -u postgres psql -c "DROP DATABASE paperless;"
sudo -u postgres psql -c "CREATE DATABASE paperless OWNER paperless;"
sudo mv /diskpool/paperless /diskpool/paperless.broken
sudo systemd-tmpfiles --create   # recreates /diskpool/paperless empty
sudo systemctl start paperless-web.service   # runs migrations on start
sudo systemctl stop paperless-web.service

sudo -u paperless paperless-manage document_importer /tmp/restore/diskpool/paperless-export
```

## 4b. Route B: Restore the Database Dump

```bash
sudo restic-b2 config restore <CONFIG_SNAPSHOT_ID> \
  --target /tmp/restore \
  --include /diskpool/configuration/postgresql

sudo -u postgres psql -c "DROP DATABASE paperless;"
sudo -u postgres psql -c "CREATE DATABASE paperless OWNER paperless;"
sudo zcat /tmp/restore/diskpool/configuration/postgresql/all.sql.gz \
  | sudo -u postgres psql paperless
```

If the media files are lost too, restore them from the `paperless` repo (`--include /diskpool/configuration/paperless/media`) and copy them back into `/diskpool/paperless` with owner `paperless`. Pick the `paperless` snapshot from the same night as the `config` snapshot so files and DB rows match.

---

## 5. Verify & Restart

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

## 6. Cleanup

```bash
sudo rm -rf /tmp/restore
```

---

## Notes

- `paperless-exporter.service` stops the four Paperless services while it runs and starts them again afterwards, pass or fail. Never call it from inside `backup-job`, or it brings Paperless back up in the middle of the backup.
- Live media files are at `/diskpool/paperless` (`services.paperless.mediaDir`); `/diskpool/configuration/paperless` is the nightly rsync copy, not the live tree.
- The `config` repo excludes `/diskpool/configuration/paperless`; Paperless files go only to the `paperless` repo.
- Restic credentials are managed by **agenix**.
