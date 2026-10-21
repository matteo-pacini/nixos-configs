# Nexus PostgreSQL Collation Handbook

What to do when PostgreSQL on Nexus starts logging `collation version
mismatch` after a nixpkgs bump.

## Quick Reference

| Item | Value |
|------|-------|
| Server | PostgreSQL 17, `hosts/Nexus/services/postgresql.nix` |
| Default collation | glibc locale (`en_GB.UTF-8`) |
| Trigger | nixpkgs bump that changes the glibc version |
| Symptom | `WARNING: database "<db>" has a collation version mismatch` on every connection |
| Fix | reindex each database, then `REFRESH COLLATION VERSION` ([Fix](#fix)) |
| Run as | `matteo` on Nexus, bash or zsh (the quoting does not work in fish) |

## What a collation is

A collation is the set of rules for comparing and sorting text: whether
`a` sorts before `B`, where `é` goes relative to `e`, how `-` and spaces
are weighed. Each database has a default collation that every text column
uses unless it says otherwise.

PostgreSQL does not implement those rules itself; for the default libc
provider it asks glibc to compare strings. glibc occasionally changes its
sort rules between releases.

## Why it matters

A B-tree index on a text column stores values in sorted order, and that
order was computed with the glibc rules in force when the index was
built. If a newer glibc sorts some strings differently, the index no
longer matches the comparisons the server makes at query time:

- lookups can miss rows that are in the table,
- unique constraints can let duplicates in,
- range scans and `ORDER BY` served from the index can return the wrong rows.

Nothing crashes. The corruption is silent, which is why PostgreSQL warns.

PostgreSQL records the collation version each database was created or
last refreshed with (`pg_database.datcollversion`) and compares it with
what glibc reports on every connection. The warning repeats until the
recorded version is refreshed.

The fix is always two steps, in this order:

1. **`REINDEX`** rebuilds the indexes with the current glibc rules.
2. **`ALTER DATABASE … REFRESH COLLATION VERSION`** records that the
   database now matches, which stops the warning.

Running only step 2 silences the warning and leaves the indexes possibly
wrong. Never do that.

## Check

Which databases are affected, from the journal (no sudo needed):

```bash
journalctl -b -u postgresql.service -g "collation version mismatch" -o cat \
  | grep -o 'database "[^"]*"' | sort | uniq -c
```

Recorded against current version, per database:

```bash
sudo -u postgres psql -c "select datname, datcollversion, pg_database_collation_actual_version(oid) from pg_database order by 1"
```

A database is fixed when the two version columns agree.

## Fix

Paste into a shell on Nexus (bash or zsh). It asks for the sudo password
once, then goes through every database that accepts connections, in name
order:

```bash
sudo -v && for db in $(sudo -u postgres psql -Atc "select datname from pg_database where datallowconn order by datname"); do echo "== $db"; sudo -u postgres env PGOPTIONS="-c client_min_messages=error" psql -v ON_ERROR_STOP=1 -d "$db" -c "REINDEX DATABASE CONCURRENTLY \"$db\"" -c "ALTER DATABASE \"$db\" REFRESH COLLATION VERSION" || break; done; sudo -u postgres env PGOPTIONS="-c client_min_messages=error" psql -c "select datname, datcollversion from pg_database order by 1"
```

How it behaves:

- **Reindex before refresh, per database.** A database is only marked
  current after its indexes were rebuilt.
- **`|| break`** stops at the first failure, so no later database is
  refreshed on top of an error you have not looked at.
- **`PGOPTIONS="-c client_min_messages=error"`** hides the mismatch
  warning, which otherwise prints once per connection and buries the
  output.
- **The final query** prints every database's recorded version. Every row
  except `template0` should show the new glibc version.

To resume after a failure, add `and datname >= '<db>'` to the inner
`select`, where `<db>` is the database that failed:

```bash
... where datallowconn and datname >= 'hass' order by datname ...
```

Databases that sort before it are already done and are skipped.

## Why `CONCURRENTLY`: the deadlock

Plain `REINDEX DATABASE` takes an `ACCESS EXCLUSIVE` lock on each table
while it rebuilds that table's indexes. On 2026-10-21 that deadlocked
against Home Assistant's recorder, which writes to `hass` continuously:

```
ERROR:  deadlock detected
DETAIL:  Process 8256 waits for AccessExclusiveLock on relation 18604 of database 16384; blocked by process 6429.
Process 6429 waits for RowExclusiveLock on relation 18599 of database 16384; blocked by process 8256.
```

The reindex held one `hass` table and wanted another; the recorder held
the second and wanted the first. PostgreSQL killed the reindex.

That failure is safe. `REINDEX DATABASE` commits table by table, so
tables finished before the deadlock keep their new indexes and the one
in progress rolls back. The collation version is not refreshed, so the
warning stays until a later run succeeds.

`REINDEX … CONCURRENTLY` builds each new index alongside the old one and
swaps them, holding only locks that let reads and writes continue. It is
slower and uses more disk while it runs, but every Nexus service can stay
up. That is why the [Fix](#fix) command uses it.

## Cleanup after a failed concurrent run

If a `REINDEX … CONCURRENTLY` is interrupted, the half-built replacement
stays behind as an invalid index whose name ends in `_ccnew` (or
`_ccold` for an old one not yet dropped). Find them in the database that
failed:

```bash
sudo -u postgres psql -d <db> -c "select indexrelid::regclass from pg_index where not indisvalid"
```

Drop each one, then resume the loop from that database:

```bash
sudo -u postgres psql -d <db> -c 'drop index concurrently "<schema>"."<index_ccnew>"'
```

## Expected leftovers

- **`template0`** keeps the old version. It does not accept connections,
  so the loop skips it. Nothing is created from it unless you ask for it
  explicitly (`createdb -T template0`), so the stale version is harmless.
- **System catalogs** are skipped by `CONCURRENTLY` with a notice. Their
  text columns use the `name` type with the `C` collation, which is plain
  byte order and never changes with glibc.

## Changelog

| Date | glibc | Trigger | Notes |
|------|-------|---------|-------|
| 2026-10-21 | 2.42 → 2.44 | Weekly flake update, PR #416 | Plain `REINDEX` loop finished `atticd`, `atuin`, `grafana`, then deadlocked on `hass`; resumed from `hass` with `CONCURRENTLY`, which finished the rest |
