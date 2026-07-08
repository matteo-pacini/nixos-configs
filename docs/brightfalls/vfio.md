# VFIO GPU Passthrough Handbook

Single-GPU passthrough of the RX 6800 XT eGPU to libvirt VMs on
BrightFalls. The host has no usable second GPU, so the desktop goes
away while a passthrough VM runs and comes back when it stops.

Config lives in `hosts/Brightfalls/virtualization.nix`
(specialisation `VFIO` + qemu hook). Restored and reworked in 2026-07
from the unmerged `um890pro-vfio` branch (tip `a3d8144`).

## Hardware topology

| Device | PCI address | IDs | IOMMU group | Driver (normal) |
|--------|-------------|-----|-------------|-----------------|
| dGPU video (RX 6800 XT, Navi 21) | `0000:07:00.0` | `1002:73bf` | 21 | `amdgpu` |
| dGPU HDMI audio | `0000:07:00.1` | `1002:ab28` | 22 | `snd_hda_intel` |
| iGPU video (Radeon 780M) | `0000:0a:00.0` | `1002:1900` | 23 | *none bound* |
| iGPU HDMI audio | `0000:0a:00.1` | `1002:1640` | 24 | `snd_hda_intel` |

- The eGPU hangs off Thunderbolt: `00:02.4 → 05:00.0 → 06:00.0 →
  07:00.0` (own PCIe switch). Video and audio functions sit in their
  own IOMMU groups — clean isolation, no ACS override needed.
- **All monitors are on the dGPU** (DP-1, DP-2, HDMI-1 = Evanlak
  dummy). The iGPU has no driver bound and no DRM node — it cannot
  drive a display. This is why the setup is true single-GPU
  passthrough: while the VM owns the GPU the host is reachable via
  SSH only.
- PCI addresses have been renumbered before (the old back-USB
  controller `c8:00.3` no longer exists — see *Known gaps*). If
  passthrough suddenly fails with "node device not found", re-check
  addresses:

  ```bash
  for d in /sys/bus/pci/devices/*; do
    echo "$(basename $d) $(cat $d/class) $(basename $(readlink $d/driver 2>/dev/null) 2>/dev/null)"
  done | grep 0x03    # display controllers
  ```

## Architecture

Hybrid design: a NixOS **specialisation** provides the boot-time
plumbing (kernel params, hugepage size, VBIOS, conflict-service
shutdown), and a **libvirt qemu hook** does the actual GPU
detach/reattach at VM start/stop. There is no boot-time
`vfio-pci.ids=` bind — `amdgpu` owns the card at boot, so the host
desktop works normally in VFIO mode until a passthrough VM starts.

```
GRUB: "NixOS - (VFIO - …)"             GRUB: "NixOS" (default)
        │                                      │
        ▼                                      ▼
GNOME desktop, normal use              no passthrough available
        │
        │  virsh start NAME-with-gpu-XX
        ▼  hook "prepare"
verify XX × 1G hugepages are free (pool of 16 reserved at boot)
→ start libvirt-nosleep → pin host slices to CPUs 0,8
→ [skip to vfio load if GPU already on vfio-pci]
→ stop display-manager → unbind fb vtconsoles
→ wait ≤30 s until /dev/dri/card*+renderD* have no users (fuser)
→ modprobe -r amdgpu
→ virsh nodedev-detach 07:00.0 + 07:00.1
→ modprobe vfio vfio_pci vfio_iommu_type1
        │
        ▼  VM runs — host headless, SSH only, CPUs 1-7,9-15 for VM
        │
        ▼  hook "release" (VM shutdown)
unload vfio modules → PCI bus reset on 07:00.0 (skipped if amdgpu
still bound) → nodedev-reattach both functions → modprobe amdgpu
→ rebind vtconsoles → restart display-manager
→ unpin CPUs (0-15) → stop libvirt-nosleep
```

The hook sends GNOME notifications where a session exists to receive
them (best effort — during most of the flow the desktop session is
down). Failure semantics differ by phase: in **prepare**, any failed
critical step aborts the VM start with a critical-urgency
notification pointing at `/var/log/libvirt/gpu-passthrough-hook.log`; in
**release**, every step is deliberately best-effort (`|| true`) so
the hook restores as much of the host as possible — release failures
are therefore *silent* and show up as symptoms (see
*Troubleshooting*), not notifications. Both phases leave a full
`set -x` trace in `/var/log/libvirt/gpu-passthrough-hook.log`.

### Why this design and not early vfio-pci bind

An early-bind specialisation (vfio-pci claims the GPU from initrd)
never exercises the AMD reset path and is the most reliable pattern —
but on this host it would mean **no display at all** from boot, since
the iGPU is inert. The hook approach keeps the desktop until the VM
actually starts. Navi 21 (RDNA2) resets cleanly via PCI secondary
bus reset (`cat /sys/bus/pci/devices/0000:07:00.0/reset_method` →
`bus`; the card advertises no FLR, and BACO is only reachable through
a loaded amdgpu), which makes runtime detach/reattach viable; on a
card with reset-bug trouble the early-bind pattern would be the
fallback.

## Usage

1. Reboot and pick the **NixOS - (VFIO - …)** entry in GRUB (the
   specialisation is labelled by its name and date, not by hostname).
2. Name the VM with the convention `NAME-with-gpu-XX` where `XX` is
   the guest RAM in GiB, e.g. `win11-with-gpu-16`. It must fit the
   16-page hugepage pool reserved at boot (`staticHugepages` in
   `virtualization.nix`). **Run only one `-with-gpu` VM at a
   time** — the hook is stateless and a second VM's prepare/release
   would reset the GPU out from under the first.
3. In the domain XML: pass through hostdevs `0000:07:00.0` and
   `0000:07:00.1` with **`managed='no'`** (the hook owns
   detach/reattach ordering; with `managed='yes'` libvirt reattaches
   the GPU on VM stop on its own schedule, racing the hook's
   reset-then-reattach sequence); point the GPU hostdev at the VBIOS
   with `<rom file="/run/libvirt/vbios/rx6800xt.rom"/>`; enable
   `<memoryBacking><hugepages/></memoryBacking>`; pin vCPUs to host
   CPUs 1-7 and 9-15 (`<cputune>`) — the hook reserves 0 and 8 for
   the host.
4. `virsh start win11-with-gpu-16` (or virt-manager). Screen goes
   black, monitors light up with VM output.
5. Shut the VM down from inside the guest; GNOME comes back
   automatically. GDM restart re-rolls the mutter primary-monitor
   pick — if a wrong monitor comes up primary, see *Troubleshooting*.

The VM domain XML itself is not managed declaratively (see the
NixVirt flake if that ever becomes desirable).

## Guest XML reference

The parts of the domain XML that are specific to this host
(`win11-with-gpu-16`, 16 GiB / 14 vCPUs). Host CPU is a Ryzen 9
8945HS: 8 cores × 2 threads, SMT sibling pairs `N,N+8`. The hook
keeps core 0 (threads 0,8) for the host, so the guest gets cores 1-7
as 7 cores × 2 threads, pinned to the real sibling pairs:

```xml
<memory unit="GiB">16</memory>
<memoryBacking>
  <hugepages>
    <page size="1" unit="GiB"/>
  </hugepages>
</memoryBacking>

<vcpu placement="static">14</vcpu>
<cputune>
  <!-- adjacent vcpu pairs = one physical core (threads N,N+8) -->
  <vcpupin vcpu="0"  cpuset="1"/>  <vcpupin vcpu="1"  cpuset="9"/>
  <vcpupin vcpu="2"  cpuset="2"/>  <vcpupin vcpu="3"  cpuset="10"/>
  <vcpupin vcpu="4"  cpuset="3"/>  <vcpupin vcpu="5"  cpuset="11"/>
  <vcpupin vcpu="6"  cpuset="4"/>  <vcpupin vcpu="7"  cpuset="12"/>
  <vcpupin vcpu="8"  cpuset="5"/>  <vcpupin vcpu="9"  cpuset="13"/>
  <vcpupin vcpu="10" cpuset="6"/>  <vcpupin vcpu="11" cpuset="14"/>
  <vcpupin vcpu="12" cpuset="7"/>  <vcpupin vcpu="13" cpuset="15"/>
  <emulatorpin cpuset="0,8"/>
</cputune>

<cpu mode="host-passthrough" check="none" migratable="on">
  <topology sockets="1" dies="1" clusters="1" cores="7" threads="2"/>
  <cache mode="passthrough"/>
</cpu>

<!-- Hyper-V enlightenments for a Windows guest; spinlocks state="on"
     requires the retries attribute or libvirt rejects the XML -->
<features>
  <acpi/>
  <apic/>
  <hyperv mode="custom">
    <relaxed state="on"/>
    <vapic state="on"/>
    <spinlocks state="on" retries="8191"/>
    <vpindex state="on"/>
    <runtime state="on"/>
    <synic state="on"/>
    <stimer state="on"/>
    <frequencies state="on"/>
    <tlbflush state="off"/>
    <ipi state="off"/>
    <avic state="on"/>
  </hyperv>
  <vmport state="off"/>
</features>

<clock offset="localtime">
  <timer name="hpet" present="yes"/>
  <timer name="hypervclock" present="yes"/>
</clock>

<!-- GPU + its audio function; managed='no' — the hook owns
     detach/reattach ordering. ROM only on the GPU function. -->
<hostdev mode="subsystem" type="pci" managed="no">
  <source>
    <address domain="0" bus="7" slot="0" function="0"/>
  </source>
  <rom bar="on" file="/run/libvirt/vbios/rx6800xt.rom"/>
</hostdev>
<hostdev mode="subsystem" type="pci" managed="no">
  <source>
    <address domain="0" bus="7" slot="0" function="1"/>
  </source>
  <rom bar="off"/>
</hostdev>
```

## Specialisation details

Only active in VFIO mode (`system.nixos.tags = [ "with-vfio" ]`):

- **Disabled services** (conflict with passthrough):
  `services.sunshine`, `services.lact`,
  `hardware.amdgpu.overdrive` — all `mkForce false`.
- **Kernel params**:
  `vfio_iommu_type1.allow_unsafe_interrupts=1`, `kvm.ignore_msrs=1`,
  `default_hugepagesz=1G`, `hugepagesz=1G`, `hugepages=16` (AMD-Vi is
  on by default and `iommu=pt` is already set host-wide in
  `hardware.nix`). The 16 × 1 GiB hugepage pool is reserved at boot
  and held for the whole VFIO session — of the ~29 GiB the host has
  (32 GiB minus the 780M iGPU carve-out), ~13 GiB remain for the
  host. The hook only verifies the pool covers the VM; it never
  allocates or frees pages. Size is `staticHugepages` in
  `virtualization.nix`.
- **VBIOS**: `extra/Asus.RX6800XT.16384.201104.rom` is linked to
  `/run/libvirt/vbios/rx6800xt.rom` via tmpfiles. Needed because the
  eGPU's ROM is shadowed after host boot. Verified valid (2026-07):
  `55 AA` option-ROM magic, PCIR vendor/device `1002:73bf` (matches
  the passed GPU), legacy-image checksum 0, image chain = 1 x86
  legacy + 2 UEFI GOP images, correctly terminated. Dump identifies
  as ASUS TUF RX6800XT O16G (`NAVI21EXT`, part `115-D412BS0-101`).
- **libvirt logging**: qemu warnings+ to
  `/var/log/libvirt/libvirtd.log`. Note libvirt discards hook
  stdout/stderr unconditionally (no output buffer is passed to hook
  invocations) — only a generic one-line error reaches libvirtd.log
  when a hook fails, and nothing at all on success.
- **hook logging**: the hook redirects its own stdout/stderr
  (including the `set -x` trace) to
  `/var/log/libvirt/gpu-passthrough-hook.log`, one timestamped
  header per invocation. Appends forever, no rotation — volume is a
  few KB per VM start/stop, revisit if it ever matters.
- **libvirt-nosleep.service**: systemd-inhibit block on sleep while a
  passthrough VM runs (belt-and-braces — suspend is also disabled
  host-wide in `hosts/Brightfalls/default.nix`, because the eGPU
  never survives suspend).

The hook script is installed declaratively via
`virtualisation.libvirtd.hooks.qemu."gpu-passthrough"`; the
`libvirtd-config` unit symlinks it into
`/var/lib/libvirt/hooks/qemu.d/gpu-passthrough` at activation.

## Changes vs the original (um890pro-vfio branch)

| Change | Reason |
|--------|--------|
| Static 16 × 1G hugepage pool at boot (`hugepages=16`) | Dynamic per-VM allocation could not assemble 16 contiguous 1 GiB blocks once the session had fragmented memory (best effort 12/16); boot-time reservation always succeeds. Hook only verifies pool size. |
| Dropped `vendor-reset` module | Supports only Polaris/Vega/Navi10-14 — not Navi 21. Unmaintained, with build breakage reported across recent kernels (host runs 7.x). Plain PCI bus reset is sufficient for RDNA2. |
| `fuser` wait-loop before `modprobe -r amdgpu` | Fixed `sleep`s raced against session teardown; any process still holding `/dev/dri/*` made the unload fail. Now waits up to 30 s and hard-fails with a notification instead of proceeding blind. |
| Prepare-phase vfio-pci safety net | If a previous release failed, the GPU is still bound to vfio-pci at the next start. The hook now detects this and skips the display-manager/unbind/detach steps instead of erroring out. |
| Release resets only an unbound GPU | The bus reset is skipped when the GPU is still bound to amdgpu (possible after a prepare that failed early) — resetting a device under a live driver wedges it (ring timeouts, reboot-only). |
| `systemctl restart` display-manager on release | Plain `start` no-ops if GDM survived a skipped prepare and is running against a vanished GPU; `restart` forces re-initialization. |
| Notification lookups guarded | `loginctl`/`id` command substitutions in the notify helper run under `set -e`; a hiccup there used to be able to abort the whole release path. Now `\|\| true`-guarded. |
| Dropped USB controller `c8:00.3` detach | Address no longer exists after PCI renumbering. See *Known gaps*. |
| `systemd.sleep.settings.Sleep` instead of `extraConfig` | `extraConfig` is an eval-time assertion failure on NixOS 26.11. |
| Removed `isVM` plumbing | The VM build variants were removed in `c06162b`. |

## Troubleshooting

**Collect everything first.** The VFIO specialisation ships
`vfio-collect-logs` — it dumps GPU/PCI state, IOMMU groups, libvirt
and QEMU logs, kernel logs for the current *and previous* boot (for
post-crash analysis), hook execution traces and hugepages state into
a single timestamped file:

```bash
sudo vfio-collect-logs <vm-name> [output-dir]   # default output: $HOME
```

**VM start fails, notification "Step: gpu_busy_after_wait".**
Something still holds the GPU 30 s after GDM stopped. Find it over
SSH: `fuser -v /dev/dri/card* /dev/dri/renderD*`. Usual suspects:
lingering `gnome-shell`/`gjs`/Xwayland, a game, Sunshine (should be
mkForced off in this specialisation). Kill it and start the VM again.

**VM start fails at `unload_amdgpu`.** Same cause as above if fuser
missed a kernel-side user. `dmesg | tail` will name the blocker.

**Any failed prepare leaves the host degraded.** A prepare that
aborts after stopping the display manager exits with GDM down, host
CPUs pinned to 0,8 and libvirt-nosleep running —
the hook does not roll these back, and whether libvirt then invokes
the release phase is version-dependent. Recover over SSH:

```bash
systemctl restart display-manager.service
systemctl set-property --runtime -- user.slice AllowedCPUs=0-15
systemctl set-property --runtime -- system.slice AllowedCPUs=0-15
systemctl set-property --runtime -- init.scope AllowedCPUs=0-15
systemctl stop libvirt-nosleep.service
```

**Screen stays black after VM shutdown.** The release path failed
partway — and release failures are silent by design (every step is
`|| true`), so there is no notification to expect. Check
`/var/log/libvirt/gpu-passthrough-hook.log` for the trace, and
`dmesg` for `amdgpu` ring timeouts (`ring gfx timeout`, error
`-110`) — that is a failed GPU reset and only a host reboot recovers
it. If dmesg is clean, retry manually:

```bash
virsh nodedev-reattach pci_0000_07_00_0
virsh nodedev-reattach pci_0000_07_00_1
modprobe amdgpu
systemctl restart display-manager.service
```

**GPU stuck on vfio-pci after a failed release.** Not fatal: the next
`prepare` detects it and goes straight to VM start. To recover the
desktop instead, run the manual reattach above.

**VM start fails, notification "hugepages_pool".** `XX` exceeds the
free pages in the boot-reserved pool — either the VM name asks for
more than 16, or another `-with-gpu` VM is holding pages. Use a
smaller `XX`, or raise `staticHugepages` in `virtualization.nix` and
rebuild (each page permanently takes 1 GiB from the host for the
whole VFIO session).

**Wrong monitor primary after GNOME comes back.** Known mutter 50
regression (it can ignore the HDMI-1 `<disabled>` entry in
`monitors.xml` on a fresh GDM start and pick the Evanlak dummy as
primary). Fix from a terminal:

```bash
gdctl set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 \
          --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951
```

**"Node device not found" on detach.** PCI addresses changed (BIOS
update, Thunderbolt re-enumeration, `pci=assign-busses` effects).
Re-map with the command in *Hardware topology* and update the
addresses in `virtualization.nix` (hook + comments) and this file.

**Guest-initiated shutdown skipped the release phase.** Rare libvirt
hook quirk. Symptoms identical to a failed release; recover manually
as above.

## Known gaps / future work

- **USB passthrough**: the original hook detached back-panel USB
  controller `c8:00.3` for the VM. That address is gone; current
  candidates are `0a:00.3`, `0a:00.4` (APU bus) and `0c:00.3`,
  `0c:00.4` (each in its own IOMMU group). Identify which controller
  owns the physical ports you want (plug a device, `readlink
  /sys/bus/usb/devices/usb*` → PCI address) and re-add the
  detach/reattach pair to the hook.
- **Looking Glass**: unusable here — it needs a host GPU to display
  the client, and the iGPU cannot drive a monitor.
- **iGPU investigation**: `0a:00.0` has no driver bound at all
  (amdgpu ignores it). If it could be brought up (BIOS setting?), the
  host could keep a display during VM runs and Looking Glass would
  become an option.
- **CPU pinning is convention, not enforcement**: the hook restricts
  host slices to CPUs 0,8 but the guest's `<cputune>` pinning must be
  maintained by hand in the domain XML.
- **No concurrency guard**: the hook is stateless; hugepage
  allocation is absolute (not additive) and any release resets the
  GPU and frees the pool regardless of other guests. One `-with-gpu`
  VM at a time (also stated in *Usage*).
- **Failed prepare is not rolled back**: see *Troubleshooting* for
  the manual recovery sequence.

## History

| Commit | What |
|--------|------|
| `c8a13d1` (2026-01, PR #94) | Original VFIO single-GPU passthrough (desktop-attached 6800 XT, static 20×1G hugepages) |
| `882ce29` (2026-01, PR #106) | Removed — host migrated to UM890 Pro mini-PC, no dGPU |
| `88a32c5` (branch `um890pro-vfio`) | Re-added for the Thunderbolt eGPU, dynamic hugepages, notifications |
| `cd516a0` … `a3d8144` (same branch, unmerged) | Conflict-service mkForces, hugepage retries, USB detach, suspend disable |
| 2026-07 (this restore) | Branch tip revived on master with the changes listed above |
