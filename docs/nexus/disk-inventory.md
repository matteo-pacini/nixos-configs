# Nexus Disk Inventory

Provenance record for every drive in the Nexus pool: where it came from,
what it cost, what warranty it carries, and which pool slot it currently
occupies.

Companion to [`diskpool-handbook.md`](diskpool-handbook.md) (steady-state
layout) and [`disk-failure-handbook.md`](disk-failure-handbook.md)
(retirement and replacement procedure).

> **What does not go in this file.** No order numbers, marketplace
> account names, payment methods, delivery addresses, or tracked
> marketplace URLs. Vendor, date, price and warranty end are recorded
> because they are needed to make a warranty claim and to reason about
> lifecycle cost — nothing beyond that.

> **Drives are keyed by serial, not by `/dev/sdX`.** Kernel names
> reshuffle across reboots; the pool addresses data disks by LUKS mapper
> name and parity by filesystem UUID. The serial is the only stable
> physical identity.

---

## Purchase batches

| Batch | Date | Qty | Item | Condition | Source | Each | Batch total | Warranty |
|-------|------|-----|------|-----------|--------|------|-------------|----------|
| **B1** | 2020-04-20 | 2 | WD Red 8TB `WD80EFAX` | New | Amazon (Box Online Technology Store) | £263.99 | £492.78 *(after £35.20 promo)* | expired — 3 yr to 2023-04 |
| **B2** | 2020-04-23 | 2 | WD Red 8TB `WD80EFAX` | *likely used* | marketplace seller | £213.49 | £426.98 | none |
| **B3** | 2020-10-23 | 3 | WD Elements 10TB desktop external → **shucked** | New | Amazon.co.uk | £152.99 | £458.97 | expired — enclosure only, void on shucking |
| **B4** | 2022-08-25 | 2 | WD Elements 10TB desktop external → **shucked** | New | Amazon.co.uk | £169.99 | £339.98 | expired — enclosure only, void on shucking |
| **B7** | 2023-11-27 | 2 | Crucial MX500 2TB SFF SATA SSD | New | Bargain Hardware | £117.00 | £234.00 | **active — 5 yr to 2028-11** |
| **B5** | 2023-11-27 | 3 | 10TB SAS, listed as HGST `0F27385` | Used, "100% health" | charity reseller (marketplace) | £85.50 | £256.50 | none |
| **B6** | 2026-09-19 | 2 | WD `HUH721010AL4200` + `WUS721010AL5204` 10TB SAS | Excellent-Refurbished | Techbuyer Limited | £199 / £225 | £424.00 | **1 yr to 2027-09; returns to 2026-10-22** |

**Lifetime spend on drives: £2,633.21 across 16** (15 in service plus one
retired).

**B7 arrived inside the server itself.** The two root SSDs were ordered
as part of the Nexus chassis — a Dell PowerEdge R730xd, 2U, **12× 3.5"
LFF front bays plus 2× 2.5" SFF rear bays**, with an H730p RAID
controller. The SSDs occupy the two rear SFF bays as the mdadm root
mirror; the pool HDDs fill the front LFF bays. Their Crucial 5-year
warranty ran to 2028-11 but is attached to the chassis purchase, not
bought separately.

> **The chassis has 12 front bays and the pool will fill all 12.** Nine
> data disks plus two parity is 11; restoring `disk1` from B6 takes it
> to 12. After that there is no spare bay — any further growth means
> replacing a disk with a larger one, not adding one.

Nexus was assembled on a single day: B5 (the three SAS pool drives) and
B7 (the chassis with its root SSDs) were both ordered 2023-11-27.

**B3 / B4 are shucked externals.** Both were bought as WD Elements
desktop enclosures and the drive removed. B3 yielded `WD101EMAZ`
(air-filled, 5400-class); B4 yielded `WD101EDBZ` (7200 rpm). Shucking
voids the enclosure warranty, which is why these show as expired
regardless of date.

**B5 model discrepancy.** The listing described HGST `0F27385`; the
drives report as `NETAPP X377_HLBRE10TA07` (NetApp-badged HGST Ultrastar
He10, `HUH721010AL` series). Consistent with a recycler selling
OEM-badged stock under a generic part number. They arrived with roughly
4.8 years already on the clock — power-on now reads 7.59 years against
2.81 years of service here.

---

## Slot map

| Slot | Serial | Model | Batch | In service | Power-on | Health |
|------|--------|-------|-------|-----------|----------|--------|
| `/mnt/disk0` | `7PHSNSNG` | NETAPP X377_HLBRE10TA07 (SAS) | B5 | 2023-11 | 7.59 y | clean |
| `/mnt/disk1` | `JEH3ZN0M` | WDC HUH721010AL4200 (DC HC510, SAS, **4Kn**) | **B6** | 2026-09-24 | 5.48 y | clean — burn-in PASS |
| `/mnt/disk2` | `7PHSNJKG` | NETAPP X377_HLBRE10TA07 (SAS) | B5 | 2023-11 | 7.59 y | clean |
| *(retired)* | *not recorded* | NETAPP X377_HLBRE10TA07 (SAS) | B5 | 2023-11 | — | **removed 2026-05-27** |
| *(retired)* | `VCGYDYTP` | WDC WD101EMAZ-11G7DA0 | B3 | 2020-11 | 5.84 y | **removed 2026-09-22** — 48 pending, 6 offline uncorrectable |
| `/mnt/disk3` | `VCH3BK7P` | WDC WD101EMAZ-11G7DA0 | **B3** | 2020-11 | 5.84 y | clean |
| `/mnt/disk4` | `VDJDW6VK` | WDC WD80EFAX-68KNBN0 (air) | **B1** *(inferred)* | 2020-05 | 6.20 y | clean |
| `/mnt/disk5` | `VDHWAUTK` | WDC WD80EFAX-68KNBN0 (air) | **B1** *(inferred)* | 2020-05 | 6.20 y | clean |
| `/mnt/disk6` | `7HKTAXLN` | WDC WD80EFAX-68LHPN0 (helium) | **B2** *(inferred)* | 2020-05 | 6.86 y | clean |
| `/mnt/disk7` | `7HKT9MEN` | WDC WD80EFAX-68LHPN0 (helium) | **B2** *(inferred)* | 2020-05 | 6.85 y | clean |
| `/mnt/disk8` | `VCKH6UJP` | WDC WD101EDBZ-11B1DA0 | **B4** | 2022-09 | 4.01 y | clean, 58 °C max |
| `/mnt/disk9` | `VCKGXLUP` | WDC WD101EDBZ-11B1DA0 | **B4** | 2022-09 | 4.02 y | clean, 60 °C max |
| `/mnt/parity1` | `VCJXZ6RP` | WDC WUS721010AL5204 (DC HC330, SAS) | **B6** | 2026-09-23 | 0.00 y (50 h) | clean — burn-in PASS |
| `/mnt/parity2` | `VCH3DMHP` | WDC WD101EMAZ-11G7DA0 | **B3** | 2020-11 | 5.84 y | clean |
| `/` (md raid1) | `2308E6B0D773` | Crucial CT2000MX500SSD1 | **B7** | 2023-12 | 2.79 y | clean, 22 % of TBW used |
| `/` (md raid1) | `2308E6B0DA68` | Crucial CT2000MX500SSD1 | **B7** | 2023-12 | 2.78 y | clean, 24 % of TBW used |

### How the B1/B2 split was inferred

Four `WD80EFAX` drives were bought three days apart in April 2020 — two
new from Amazon (B1), two from a marketplace seller at £50 less (B2).
The purchase records alone cannot say which pair is which, but the
power-on hours can:

- The April 2020 delivery date caps possible power-on at **~56,100 h**.
- `VDHWAUTK` / `VDJDW6VK` read **54,308 h** — 97 % duty since purchase.
  Consistent with new drives.
- `7HKTAXLN` / `7HKT9MEN` read **60,152 / 60,052 h** — about **4,000 h
  more than the calendar allows**. They cannot have been new in April
  2020, so they arrived with ~5 months already on them.

That points the cheaper marketplace pair (B2) at the two helium drives.
It is an inference, not a record: an unrecorded earlier purchase would
explain the hours equally well.

### All slots traced

Every drive in the array now maps to a dated purchase. Two earlier
candidates for the root SSDs were checked and ruled out; recorded so
they are not re-checked:

| Candidate | Why not |
|-----------|---------|
| Amazon, 2020-10-22 — Crucial MX500 | 1 TB `CT1000MX500SSD1`, not 2 TB |
| Bargain Hardware, 2022-11 — 2× Crucial MX500 in a Dell R620 build | 500 GB, not 2 TB; a different machine |

The only remaining gap is the **serial of the retired `disk1`**, which
was pulled in May 2026 without being recorded. Only its LUKS UUID
survives, in the git history of `hardware-extra.nix`. Capture serials at
removal from now on.

---

## B6 commissioning

| Serial | Model | Destination | Status |
|--------|-------|-------------|--------|
| `VCJXZ6RP` | WD `WUS721010AL5204` (DC HC330, 512e) | `/mnt/parity1` | **in service 2026-09-23** — burn-in PASS |
| `JEH3ZN0M` | WD `HUH721010AL4200` (DC HC510, **4Kn**) | `/mnt/disk1` | **in service 2026-09-24** — burn-in PASS |

Assignment was decided on power-on hours, not on the platform lean:
`VCJXZ6RP` arrived at **21 h** (one 10 TB certification wipe and nothing
else — effectively new old stock), against **48,017 h / 5.48 y** for
`JEH3ZN0M`. That gap is far past the ~15,000 h threshold, so the
near-new drive took the slot with no fallback.

`JEH3ZN0M` is heavily used but clean: 1.29 PB read and 270 TB written,
zero grown defects, zero uncorrected errors, and only 0.28 % of its
load-unload budget — an always-on, read-heavy datacenter life. Its
workload drops to about a quarter of that here.

**`JEH3ZN0M` shipped with writeback cache disabled** (`WCE=0`), which
held `badblocks` to 38 MB/s against 239 MB/s for `VCJXZ6RP`. Fixed with
`sdparm --set=WCE=1 --save`. The two NETAPP SAS drives on `disk0` and
`disk2` are still `WCE=0` and have been since 2023 — worth enabling once
parity is rebuilt. Every SATA drive in the pool already has it on.

Both drives are in service. Warranty runs to **2027-09**; the return
window is open until **2026-10-22**.

**Outstanding:** enable `WCE=1` on the two NETAPP SAS drives, and a
final `snapraid sync --force-empty` to bring the newly added `disk1`
into parity.

---

## Reliability reference

Manufacturer figures, gathered 2026-09-19. **None of the WD drives in
this array is a retail model** — they are white-label units pulled from
external enclosures or OEM-badged pulls, and WD publishes no reliability
specification for any of them. The substitutes below are the nearest
retail equivalents and are labelled as such.

| Model | MTBF / AFR | Workload rating | Load/unload | Warranty as sold |
|-------|-----------|-----------------|-------------|------------------|
| `WD101EMAZ` (white label) | not published | not published | not published | enclosure only |
| ↳ *substitute:* Ultrastar He10 | 2.5 M h / 0.35 % | 550 TB/yr | 600,000 | 5 yr |
| `WD101EDBZ` (white label) | not published | not published | not published | enclosure only |
| ↳ *substitute A:* Ultrastar DC HC330 | 2.0 M h / 0.44 % | 550 TB/yr | 600,000 | 5 yr |
| ↳ *substitute B:* WD Red Pro 10TB | 1.0 M h | 300 TB/yr | 600,000 | 5 yr |
| `WD80EFAX` (both revisions) | 1.0 M h | 180 TB/yr | 600,000 | 3 yr |
| `X377_HLBRE10TA07` = `HUH721010AL` | 2.5 M h / 0.35 % | 550 TB/yr | 600,000 | NetApp contract, not WD's 5 yr |
| `CT2000MX500SSD1` | 1.8 M h MTTF | **700 TBW** (≈0.19 DWPD derived) | n/a | 5 yr |

Sources: [WD He10 datasheet](https://documents.westerndigital.com/content/dam/doc-library/en_us/assets/public/western-digital/product/data-center-drives/ultrastar-hdd-sata-series/ultrastar-he10/data-sheet-ultrastar-he10.pdf),
WD Red datasheet 2879-800002,
[Crucial MX500 flyer](https://content.crucial.com/content/dam/crucial/ssd-products/mx500/flyer/crucial-mx500-ssd-productflyer-en.pdf).

Caveats worth keeping:

- **No datasheet publishes a "design service life" in years.** The
  5-year figure everyone quotes is the *warranty*. Do not treat it as a
  service-life spec.
- **`WD80EFAX` is CMR, not SMR** — WD's own recording-technology table
  puts Red 2–6 TB on SMR and 8 TB and above on CMR.
- **Helium status, settled from our own dumps:** only `7HKTAXLN` and
  `7HKT9MEN` (the `-68LHPN0` pair) expose SMART attribute 22
  `Helium_Level` (value 100). No other drive in the array does,
  including both 10 TB white-label families. Absence is suggestive, not
  conclusive — firmware may simply not surface the attribute — but it
  makes the He10 substitute above questionable for `WD101EMAZ`.
- **Load/unload rating is ambiguous.** The datasheets say 600,000. But
  attribute 193's normalized value on all nine WD drives follows
  `100 − floor(raw / 1200)`, implying the firmware scales against
  **120,000**. The percentages in the next table use 120,000, because
  that is the scale smartd's own thresholds act on. Divide by five for
  the datasheet view.

### Observed fleet data

Public large-fleet statistics, for calibration against the vendor
numbers above:

| Platform | Observed AFR | Avg age | Note |
|----------|-------------|---------|------|
| HGST He8 8TB (`HUH728080ALE600`) | 1.40 % lifetime | ~7.3 yr | **Q4 2025 spiked to 10.29 %**, then back to 0 % |
| He10 10TB | — | ~1 yr | Only 20 drives, 0 failures, 2019. No usable AFR. |
| WD Red 8TB, WD101 family | — | — | Never reported |

Source: [Backblaze Drive Stats](https://www.backblaze.com/blog/backblaze-drive-stats-for-q1-2026/).

**The age inflection has moved.** Backblaze's 2025 bathtub-curve revisit
(317,230 drives) puts years 0–1 at ~1.30 % AFR — infant mortality is
effectively gone — then flat, then a steep late spike peaking at
**4.25 % AFR at 10 yr 3 mo**. Earlier cohorts peaked much sooner (2013
cohort: 13.73 % at 3 yr 3 mo). Practical read: **the modern inflection
is 7–10 years, not 3–5.**

The He8 Q4-2025 spike is the single most relevant datapoint here — a
7-year-old helium HGST fleet ran near 0 % for years, produced one 10.29 %
quarter, then returned to 0 %. **Late-life failure on these platforms
arrives in clusters, not as a smooth ramp.**

---

## Estimated remaining life

Assessed **2026-09-19**. These are actuarial estimates for planning
replacement budget and order — not predictions about an individual
drive. Re-run the assessment yearly; the numbers age.

| Slot | Serial | Powered age | Workload used | Head-park used | Health | Est. remaining |
|------|--------|------------|---------------|----------------|--------|----------------|
| `parity1` | `VCJXZ6RP` | 0.00 y | <1 % | <1 % | clean, burn-in PASS | **7–10 y** |
| `disk2` | `7PHSNJKG` | **7.59 y** | 10 % | 0.4 % | clean | **1–3 y** |
| `disk0` | `7PHSNSNG` | **7.59 y** | 10 % | 0.4 % | clean | **1–3 y** |
| `disk6` | `7HKTAXLN` | 6.86 y | 39 % | 25 % | clean | **1–3 y** |
| `disk7` | `7HKT9MEN` | 6.85 y | 37 % | 25 % | clean | **1–3 y** |
| `disk5` | `VDHWAUTK` | 6.20 y | 38 % | 24 % | clean | 2–4 y |
| `disk4` | `VDJDW6VK` | 6.20 y | 38 % | 21 % | clean | 2–4 y |
| `parity2` | `VCH3DMHP` | 5.84 y | 42 % | 24 % | clean | **2–4 y** (batch) |
| `disk3` | `VCH3BK7P` | 5.84 y | 50 % | 15 % | clean | 3–5 y |
| `disk1` | `JEH3ZN0M` | 5.48 y | 13 % | <1 % | clean, burn-in PASS | **2–4 y** |
| `disk9` | `VCKGXLUP` | 4.02 y | 14 % | 1.2 % | clean, 60 °C max | 4–6 y |
| `disk8` | `VCKH6UJP` | 4.01 y | 13 % | 1.5 % | clean, 58 °C max | 4–6 y |
| `/` SSD | `2308E6B0D773` | 2.79 y | **22 % of TBW** | n/a | clean | 6+ y |
| `/` SSD | `2308E6B0DA68` | 2.78 y | **24 % of TBW** | n/a | clean | 6+ y |

### Method, and what actually limits these drives

**Age is the only binding constraint.** Neither of the other two
candidates is close to biting:

- *Workload* — the worst drive is at 50 % of its rating; most are under
  40 %. Annual throughput runs 57–89 TB/yr against ratings of 180 TB/yr
  (WD Red) to 550 TB/yr (enterprise).
- *Head parking* — `disk6` is the worst at 25 % consumed over 6.86
  years, i.e. ~4,335 cycles/yr. Exhausting the remaining budget would
  take another 20 years. **hd-idle is not hurting these drives.**
- *SSD endurance* — 102 and 108 TB host-written against a 700 TBW
  rating. Write amplification is 1.72–1.74×, so NAND has seen ~175 and
  ~188 TB. At the current ~38 TB/yr they have roughly 9 years of
  endurance left; power-on age will bite first.

So the estimates are driven by powered age set against the 7–10 year
inflection above, adjusted down for same-batch correlation where it
applies.

### Two drive-specific notes

- **`VCKGXLUP` / `VCKH6UJP` run hot and never stop.** Spindle-motor time
  is 99.98 % and 97.2 % of power-on, against 79–82 % for every other
  pool drive — they are effectively always spinning. Lifetime maxima of
  60 °C and 58 °C are the two highest in the array (limit 65 °C, zero
  time over temperature so far). Youngest mechanical drives, most
  thermal stress. Worth checking airflow over those bays.
- **The SAS pair's power-on counter wraps.** `smartctl` reports ~1018
  hours; the true figure is **66,554 h (7.59 y)**. The SPC self-test log
  stores power-on in a 2-byte field, so it reports hours mod 65,536. The
  literal reading is impossible because the drives' own General
  Statistics page records 40,580 hours of *idle* time, which cannot
  exceed power-on. 132,090 h is excluded by the manufacture date (week
  53 of 2016). Only 66,554 fits. **Do not read these two drives' age off
  the raw field.**

---

## Batch-risk notes

Track these when planning replacements — same-batch drives have
correlated failure.

- **B3 is three drives in two of the most critical slots.** `VCGYDYTP`
  (parity1, failing) and `VCH3DMHP` (parity2) are twins: identical
  51,197 power-on hours, near-sequential serials, 151.78 vs 151.83 TB
  written. One has failed. Treat parity2 as higher-risk than its clean
  SMART suggests. `VCH3BK7P` on disk3 is the third of that batch.
- **B5 was three drives and one has already failed** (2026-05-27, 2.5
  years after purchase). The two survivors are the oldest drives in the
  array at 7.59 years powered, ~9.7 years since manufacture (week 53 of
  2016).
- **B2's two drives are helium** (SMART attribute 22 present, absent on
  every other drive). Their nearest platform sibling in public fleet data
  showed clustered failures at ~7.3 years average age; they are at 6.86.

---

## Changelog

| Date | Event |
|------|-------|
| 2026-09-24 | `JEH3ZN0M` passed burn-in and took the restored `/mnt/disk1` slot; pool back to 10 data disks |
| 2026-09-24 | Applying the disk1 config before the device existed blocked boot before multi-user.target — recovered via previous generation at the boot menu |
| 2026-09-23 | `VCJXZ6RP` passed burn-in (0 bad blocks) and took over `/mnt/parity1`; parity rebuild follows |
| 2026-09-22 | `VCGYDYTP` pulled from `/mnt/parity1`; SnapRAID sync + scrub paused while single-parity |
| 2026-09-22 | B6 drives arrived; `JEH3ZN0M` found with WCE=0, enabled via sdparm |
| 2026-09-19 | Fleet life assessment recorded — see [Estimated remaining life](#estimated-remaining-life). Next review due 2027-09 |
| 2026-09-19 | B6 ordered — 2× 10TB SAS refurbished, £424, 1 yr warranty |
| 2026-09-19 | `VCGYDYTP` (parity1) flagged failing: 48 pending sectors, 6 offline uncorrectable |
| 2026-05-27 | B5 drive removed from `/mnt/disk1` — repeated SMART background self-test failures |
| 2023-11-27 | **Nexus built** — B5 (3× 10TB SAS, £256.50) and B7 (Dell R730xd chassis incl. 2× MX500 2TB, £234.00) ordered the same day |
| 2022-08-25 | B4 purchased — 2× WD Elements 10TB for shucking, £339.98 |
| 2020-10-23 | B3 purchased — 3× WD Elements 10TB for shucking, £458.97 |
| 2020-04-23 | B2 purchased — 2× WD Red 8TB, £426.98 |
| 2020-04-20 | B1 purchased — 2× WD Red 8TB, £492.78 |
