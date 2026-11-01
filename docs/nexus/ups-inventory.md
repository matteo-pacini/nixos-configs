# Nexus UPS Inventory

Provenance record for every UPS behind Nexus: where it came from, what it
cost, what warranty it carries, and which `apcupsd` instance monitors it.
Configuration lives in [`hosts/Nexus/services/ups.nix`](../../hosts/Nexus/services/ups.nix).

> **What does not go in this file.** No order numbers, marketplace
> account names, payment methods, delivery addresses, or tracked
> marketplace URLs. Vendor, date, price and warranty end are recorded
> because they are needed to make a warranty claim and to reason about
> lifecycle cost — nothing beyond that.

> **Units are keyed by serial.** The serial is what `apcaccess` reports, and
> Home Assistant's `apcupsd` integration derives entity identity from it, so
> swapping a unit creates new entities (see [Replacing a UPS](#replacing-a-ups)).

## In service

| Instance | Model | Serial | Link | NIS port | Manufactured |
|----------|-------|--------|------|----------|--------------|
| `server-ups` | APC SMT1500I tower with LCD (refurbished, SKU `SMT1500i-gn`) | `AS1414122787` | USB | 3552 | 2014-04-03 |
| `rack-ups` | APC SMT1000I + AP9630 NMC | `AS1213112130` | SNMP (`192.168.10.43`) | 3551 | 2012-03-28 |

`server-ups` is the only instance with shutdown triggers (10 % charge or
5 minutes remaining). `rack-ups` is monitor-only.

## Purchases

All bought on eBay UK. Warranty end is counted from delivery.

ups-trader warranty labels carry a handwritten four-digit number. On
`server-ups` it is `2787`, matching the end of its serial. The office unit's
label reads `2727`; its full serial is not recorded.

| Unit | Vendor | Ordered | Delivered | Price | Warranty end | Battery fitted |
|------|--------|---------|-----------|-------|--------------|----------------|
| `server-ups` SMT1500I | ups-trader | 2026-10-22 | 2026-10-26 | £275.00 (£550.00 for 2 units) | 2027-10-26 (12 month RTB) | New at purchase; the unit does not report a date over USB |
| Office SMT1500I, not connected to Nexus | ups-trader | 2026-10-22 | 2026-10-26 | £275.00 (same order) | 2027-10-26 (12 month RTB) | New at purchase |
| `rack-ups` SMT1000I chassis, no batteries | pro-avit.london | 2025-07-31 | 2025-08-02 | £59.79 | none recorded | n/a |
| `rack-ups` RBC6 battery pack | ups-trader | 2025-07-31 | 2025-08-05 | £67.41 | none recorded | 2025-08-15 (reported by the unit) |
| `rack-ups` AP9630 NMC | astralis-tech | 2025-07-31 | 2025-08-02 | £29.99 | none recorded | n/a |
| Second AP9630 NMC | astralis-tech | 2025-08-15 | 2025-08-21 | £29.99 | none recorded | n/a |

## Retired

| Instance | Model | Manufactured | Vendor | Ordered | Delivered | Price | Warranty end | Battery fitted | Retired | Reason |
|----------|-------|--------------|--------|---------|-----------|-------|--------------|----------------|---------|--------|
| `server-ups` | APC SMT2200I tower (refurbished) | 2011-06-12 | ups-trader | 2025-08-05 | 2025-08-13 | £356.50 | 2026-08-13 (12 month RTB) | New cells at purchase | 2026-11-01 | Failed with "output over volt" on 2026-09-04, about 3 weeks after its warranty ended |

## USB telemetry limits

Over USB, `apcaccess` reports only a subset of the fields SNMP provides. There
is no `LINEV`, `OUTPUTV`, `LOADPCT`, `LASTXFER` or `SELFTEST`, so these are
absent on `server-ups` and their absence is not a fault.

## Replacing a UPS

1. Connect the unit and confirm the model and serial with
   `server-ups-apcaccess status` (or `rack-ups-apcaccess status`).
2. Keep the configured `DEVICE` empty for USB units. `apcupsd` auto-detects
   the HID device, so `ups.nix` needs no change for a same-link swap.
3. Check Home Assistant. A new serial registers new entities with a numeric
   suffix, and anything that names the old ones must be repointed.
4. Update this file.
