{
  pkgs,
  lib,
  ...
}:
let
  # 1G hugepages reserved at boot in the VFIO specialisation
  staticHugepages = 16;

  # Generate a passthrough-ready domain XML skeleton on stdout
  vfio-vm-skeleton = pkgs.writeShellApplication {
    name = "vfio-vm-skeleton";

    runtimeInputs = with pkgs; [ coreutils ];

    text = ''
      if [ $# -lt 2 ]; then
        echo "Usage: vfio-vm-skeleton <base-name> <ram-gib> [disk.qcow2] [install.iso]" >&2
        echo "Example: vfio-vm-skeleton win11 16 /mnt/games/VMs/win11.qcow2 ~/Downloads/windows-11.iso" >&2
        echo "Define with: vfio-vm-skeleton win11 16 ... | virsh define /dev/stdin" >&2
        exit 1
      fi

      BASE_NAME="$1"
      RAM_GIB="$2"
      DISK="''${3:-}"
      ISO="''${4:-}"

      if ! [[ "$RAM_GIB" =~ ^[0-9]+$ ]] || [ "$RAM_GIB" -lt 1 ] || [ "$RAM_GIB" -gt ${toString staticHugepages} ]; then
        echo "ram-gib must be 1..${toString staticHugepages} (the boot-reserved hugepage pool)" >&2
        exit 1
      fi

      VM_NAME="$BASE_NAME-with-gpu-$RAM_GIB"

      cat <<EOF
      <domain type="kvm">
        <name>$VM_NAME</name>
        <memory unit="GiB">$RAM_GIB</memory>
        <memoryBacking>
          <hugepages>
            <page size="1" unit="GiB"/>
          </hugepages>
        </memoryBacking>
        <vcpu placement="static">14</vcpu>
        <cputune>
          <vcpupin vcpu="0" cpuset="1"/>
          <vcpupin vcpu="1" cpuset="9"/>
          <vcpupin vcpu="2" cpuset="2"/>
          <vcpupin vcpu="3" cpuset="10"/>
          <vcpupin vcpu="4" cpuset="3"/>
          <vcpupin vcpu="5" cpuset="11"/>
          <vcpupin vcpu="6" cpuset="4"/>
          <vcpupin vcpu="7" cpuset="12"/>
          <vcpupin vcpu="8" cpuset="5"/>
          <vcpupin vcpu="9" cpuset="13"/>
          <vcpupin vcpu="10" cpuset="6"/>
          <vcpupin vcpu="11" cpuset="14"/>
          <vcpupin vcpu="12" cpuset="7"/>
          <vcpupin vcpu="13" cpuset="15"/>
          <emulatorpin cpuset="0,8"/>
        </cputune>
        <os>
          <type arch="x86_64" machine="q35">hvm</type>
          <loader readonly="yes" type="pflash">/run/libvirt/nix-ovmf/edk2-x86_64-secure-code.fd</loader>
          <boot dev="hd"/>
        </os>
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
        <cpu mode="host-passthrough" check="none" migratable="on">
          <topology sockets="1" dies="1" clusters="1" cores="7" threads="2"/>
          <cache mode="passthrough"/>
        </cpu>
        <clock offset="localtime">
          <timer name="hpet" present="yes"/>
          <timer name="hypervclock" present="yes"/>
        </clock>
        <pm>
          <suspend-to-mem enabled="no"/>
          <suspend-to-disk enabled="no"/>
        </pm>
        <devices>
          <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
      EOF

      if [ -n "$DISK" ]; then
        cat <<EOF
          <disk type="file" device="disk">
            <driver name="qemu" type="qcow2"/>
            <source file="$DISK"/>
            <target dev="sda" bus="sata"/>
          </disk>
      EOF
      fi

      if [ -n "$ISO" ]; then
        cat <<EOF
          <disk type="file" device="cdrom">
            <driver name="qemu" type="raw"/>
            <source file="$ISO"/>
            <target dev="sdb" bus="sata"/>
            <readonly/>
          </disk>
      EOF
      fi

      cat <<EOF
          <controller type="usb" model="qemu-xhci" ports="15"/>
          <interface type="network">
            <source network="default"/>
            <model type="virtio"/>
          </interface>
          <console type="pty"/>
          <tpm model="tpm-crb">
            <backend type="emulator"/>
          </tpm>
          <sound model="ich9"/>
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
        </devices>
      </domain>
      EOF
    '';
  };

  # Debug log collection script for GPU passthrough troubleshooting
  vfio-collect-logs = pkgs.writeShellApplication {
    name = "vfio-collect-logs";

    runtimeInputs = with pkgs; [
      coreutils
      systemd
      libvirt
      gawk
      gnugrep
      pciutils
      procps
    ];

    text = ''
      set -euo pipefail

      # Usage check
      if [ $# -lt 1 ]; then
        echo "Usage: vfio-collect-logs <vm-name> [output-dir]"
        echo "Example: vfio-collect-logs win11-with-gpu-16"
        echo "         vfio-collect-logs win11-with-gpu-16 /tmp"
        exit 1
      fi

      VM_NAME="$1"
      OUTPUT_DIR="''${2:-$HOME}"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      OUTPUT_FILE="''${OUTPUT_DIR}/vfio-debug_''${VM_NAME}_''${TIMESTAMP}.log"

      echo "Collecting VFIO/GPU passthrough debug logs for VM: $VM_NAME"
      echo "Output file: $OUTPUT_FILE"
      echo ""

      # Create output file with header
      {
        echo "========================================================================"
        echo "VFIO/GPU PASSTHROUGH DEBUG LOG"
        echo "========================================================================"
        echo "VM Name: $VM_NAME"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "========================================================================"
        echo ""

        # --- Section 1: Current GPU and PCI State ---
        echo "========================================================================"
        echo "SECTION 1: CURRENT GPU AND PCI STATE"
        echo "========================================================================"
        echo ""

        echo "--- GPU PCI Devices (07:00.x) ---"
        lspci -nnk -s 07:00 2>/dev/null || echo "Failed to get GPU PCI info"
        echo ""

        echo "--- IOMMU Groups ---"
        for d in /sys/kernel/iommu_groups/*/devices/*; do
          if [ -e "$d" ]; then
            n="''${d#*/iommu_groups/}"; n="''${n%%/*}"
            printf 'IOMMU Group %s: ' "$n"
            lspci -nns "''${d##*/}" 2>/dev/null || echo "''${d##*/}"
          fi
        done 2>/dev/null | grep -E "(07:00|vfio|VGA)" || echo "No relevant IOMMU groups found"
        echo ""

        echo "--- GPU Reset Method ---"
        cat /sys/bus/pci/devices/0000:07:00.0/reset_method 2>/dev/null || echo "reset_method not available"
        echo ""

        echo "--- Loaded GPU/VFIO Modules ---"
        lsmod | grep -E "(amdgpu|vfio|kvm)" || echo "No relevant modules loaded"
        echo ""

        # --- Section 2: VM Status ---
        echo "========================================================================"
        echo "SECTION 2: VM STATUS"
        echo "========================================================================"
        echo ""

        echo "--- All VMs ---"
        virsh list --all 2>/dev/null || echo "Failed to list VMs"
        echo ""

        echo "--- VM '$VM_NAME' Info ---"
        virsh dominfo "$VM_NAME" 2>/dev/null || echo "VM '$VM_NAME' not found or libvirtd not running"
        echo ""

        # --- Section 3: Libvirt Logs ---
        echo "========================================================================"
        echo "SECTION 3: LIBVIRT LOGS"
        echo "========================================================================"
        echo ""

        echo "--- /var/log/libvirt/libvirtd.log (last 200 lines) ---"
        tail -n 200 /var/log/libvirt/libvirtd.log 2>/dev/null || echo "libvirtd.log not found"
        echo ""

        echo "--- /var/log/libvirt/qemu/$VM_NAME.log (last 200 lines) ---"
        tail -n 200 "/var/log/libvirt/qemu/$VM_NAME.log" 2>/dev/null || echo "VM-specific QEMU log not found"
        echo ""

        echo "--- /var/log/libvirt/gpu-passthrough-hook.log (last 300 lines) ---"
        tail -n 300 /var/log/libvirt/gpu-passthrough-hook.log 2>/dev/null || echo "gpu-passthrough-hook.log not found"
        echo ""

        # --- Section 4: Kernel Logs (Current Boot) ---
        echo "========================================================================"
        echo "SECTION 4: KERNEL LOGS - CURRENT BOOT"
        echo "========================================================================"
        echo ""

        echo "--- dmesg: GPU/VFIO related (current boot) ---"
        dmesg 2>/dev/null | grep -iE "(amdgpu|vfio|iommu|pci 0000:07|gpu|drm|reset)" | tail -n 300 || echo "No relevant dmesg entries"
        echo ""

        echo "--- dmesg: Errors and warnings (current boot) ---"
        dmesg --level=err,warn 2>/dev/null | tail -n 100 || echo "No errors/warnings in dmesg"
        echo ""

        # --- Section 5: Kernel Logs (Previous Boot) ---
        echo "========================================================================"
        echo "SECTION 5: KERNEL LOGS - PREVIOUS BOOT"
        echo "========================================================================"
        echo ""

        echo "--- journalctl -k -b -1: GPU/VFIO related (previous boot) ---"
        journalctl -k -b -1 --no-pager 2>/dev/null | grep -iE "(amdgpu|vfio|iommu|pci 0000:07|gpu|drm|reset)" | tail -n 300 || echo "No previous boot kernel logs available"
        echo ""

        echo "--- journalctl -k -b -1: Errors and warnings (previous boot) ---"
        journalctl -k -b -1 -p err --no-pager 2>/dev/null | tail -n 100 || echo "No previous boot error logs available"
        echo ""

        # --- Section 6: Journal - libvirtd Service ---
        echo "========================================================================"
        echo "SECTION 6: JOURNAL - LIBVIRTD SERVICE"
        echo "========================================================================"
        echo ""

        echo "--- Current boot ---"
        journalctl -u libvirtd -b 0 --no-pager 2>/dev/null | tail -n 150 || echo "No libvirtd journal entries"
        echo ""

        echo "--- Previous boot ---"
        journalctl -u libvirtd -b -1 --no-pager 2>/dev/null | tail -n 150 || echo "No previous boot libvirtd entries"
        echo ""

        # --- Section 7: Journal - Display Manager ---
        echo "========================================================================"
        echo "SECTION 7: JOURNAL - DISPLAY MANAGER"
        echo "========================================================================"
        echo ""

        echo "--- Current boot ---"
        journalctl -u display-manager -b 0 --no-pager 2>/dev/null | tail -n 100 || echo "No display-manager journal entries"
        echo ""

        echo "--- Previous boot ---"
        journalctl -u display-manager -b -1 --no-pager 2>/dev/null | tail -n 100 || echo "No previous boot display-manager entries"
        echo ""

        # --- Section 8: Journal - VM Name Filter ---
        echo "========================================================================"
        echo "SECTION 8: JOURNAL - VM NAME FILTER ($VM_NAME)"
        echo "========================================================================"
        echo ""

        echo "--- Current boot ---"
        journalctl -b 0 --no-pager 2>/dev/null | grep -i "$VM_NAME" | tail -n 200 || echo "No journal entries mentioning $VM_NAME"
        echo ""

        echo "--- Previous boot ---"
        journalctl -b -1 --no-pager 2>/dev/null | grep -i "$VM_NAME" | tail -n 200 || echo "No previous boot entries mentioning $VM_NAME"
        echo ""

        # --- Section 9: Journal - GPU Passthrough Hook ---
        echo "========================================================================"
        echo "SECTION 9: JOURNAL - GPU PASSTHROUGH KEYWORDS"
        echo "========================================================================"
        echo ""

        echo "--- Current boot: GPU passthrough related ---"
        journalctl -b 0 --no-pager 2>/dev/null | grep -iE "(passthrough|vfio|nodedev|detach|reattach|modprobe.*amdgpu|modprobe.*vfio)" | tail -n 150 || echo "No GPU passthrough entries"
        echo ""

        echo "--- Previous boot: GPU passthrough related ---"
        journalctl -b -1 --no-pager 2>/dev/null | grep -iE "(passthrough|vfio|nodedev|detach|reattach|modprobe.*amdgpu|modprobe.*vfio)" | tail -n 150 || echo "No previous boot GPU passthrough entries"
        echo ""

        # --- Section 10: QEMU Process Info ---
        echo "========================================================================"
        echo "SECTION 10: QEMU PROCESS INFO"
        echo "========================================================================"
        echo ""

        echo "--- Running QEMU processes ---"
        pgrep -af qemu || echo "No QEMU processes running"
        echo ""

        # --- Section 11: Hugepages Status ---
        echo "========================================================================"
        echo "SECTION 11: HUGEPAGES STATUS"
        echo "========================================================================"
        echo ""

        echo "--- Hugepages info ---"
        grep -i huge /proc/meminfo 2>/dev/null || echo "No hugepages info"
        echo ""

        echo "--- 1GB Hugepages allocation ---"
        cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || echo "1GB hugepages not available"
        cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages 2>/dev/null || echo ""
        echo ""

        # --- Section 12: System State ---
        echo "========================================================================"
        echo "SECTION 12: SYSTEM STATE AT COLLECTION TIME"
        echo "========================================================================"
        echo ""

        echo "--- Uptime ---"
        uptime
        echo ""

        echo "--- Memory ---"
        free -h
        echo ""

        echo "--- Boot entries ---"
        cat /proc/cmdline
        echo ""

        echo "========================================================================"
        echo "END OF DEBUG LOG"
        echo "========================================================================"

      } > "$OUTPUT_FILE" 2>&1

      echo "Debug log saved to: $OUTPUT_FILE"
      echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    '';
  };
in
{
  # Basic virtualization support

  virtualisation.spiceUSBRedirection.enable = true;

  users.extraUsers.matteo.extraGroups = [
    "kvm"
    "libvirtd"
  ];

  programs.virt-manager.enable = true;

  # libvirt 12.4 resolves its compiled-in default qemu user eagerly at
  # driver init (virGetUserID in virQEMUDriverConfigNew, before qemu.conf
  # is read) — 'libvirt-qemu' must exist or libvirtd dies at boot
  users.users.libvirt-qemu = {
    isSystemUser = true;
    group = "libvirt-qemu";
  };
  users.groups.libvirt-qemu = { };

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      # runAsRoot omits user/group from qemu.conf; pin them so VMs run as
      # root regardless of libvirt's compiled-in default (libvirt-qemu)
      verbatimConfig = ''
        namespaces = []
        user = "root"
        group = "root"
      '';
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };

  # VFIO specialisation for GPU passthrough
  # Boot the "NixOS - (VFIO - ...)" GRUB entry to enable GPU passthrough
  # VMs with names matching "NAME-with-gpu-XX" will trigger GPU passthrough
  # where XX is the guest RAM in GiB (must fit the boot-reserved hugepage pool)
  specialisation = {
    VFIO = {
      inheritParentConfig = true;
      configuration = {
        system.nixos.tags = [ "with-vfio" ];

        # Debug log collection + domain XML skeleton generator
        environment.systemPackages = [
          vfio-collect-logs
          vfio-vm-skeleton
        ];

        # Disable services that conflict with GPU passthrough
        services.sunshine.enable = lib.mkForce false;
        services.lact.enable = lib.mkForce false;
        hardware.amdgpu.overdrive.enable = lib.mkForce false;

        # Kernel params for IOMMU (required for GPU passthrough)
        # (iommu=pt already set host-wide in hardware.nix; AMD-Vi is on by default)
        boot.kernelParams = [
          # Allow interrupt remapping for devices without proper IOMMU support
          "vfio_iommu_type1.allow_unsafe_interrupts=1"
          # Ignore MSR access violations to prevent VM crashes (required for some AMD CPUs)
          "kvm.ignore_msrs=1"
          # Reserve 1GB hugepages for VM memory at boot
          "default_hugepagesz=1G"
          "hugepagesz=1G"
          "hugepages=${toString staticHugepages}"
        ];

        # Make VBIOS available at runtime for GPU passthrough
        systemd.tmpfiles.rules = [
          "L+ /run/libvirt/vbios/rx6800xt.rom - - - - ${./../../extra/Asus.RX6800XT.16384.201104.rom}"
        ];

        # Enhanced logging for debugging
        virtualisation.libvirtd.extraConfig = ''
          log_filters="3:qemu 1:libvirt"
          log_outputs="2:file:/var/log/libvirt/libvirtd.log"
        '';

        # GPU passthrough hook for VMs with names matching "NAME-with-gpu-XX"
        virtualisation.libvirtd.hooks.qemu = {
          "gpu-passthrough" = lib.getExe (
            pkgs.writeShellApplication {
              name = "qemu-gpu-passthrough-hook";

              runtimeInputs = with pkgs; [
                libvirt
                systemd
                kmod
                gawk
                coreutils
                gnugrep
                libnotify
                psmisc
                sudo
              ];

              text = ''
                # libvirt discards hook stdout/stderr (virRunScript passes no
                # output buffer) — self-log or every trace below is lost
                exec >> /var/log/libvirt/gpu-passthrough-hook.log 2>&1
                echo "=== $(date -Is) guest=$1 op=$2 pid=$$ ==="
                set -x  # Enable debug tracing

                GUEST_NAME="$1"
                OPERATION="$2"

                # Function to send notification to logged-in user
                notify_user() {
                  local title="$1"
                  local message="$2"
                  local urgency="''${3:-normal}"  # normal, low, critical

                  # Find the first logged-in graphical session user
                  # (|| true: notifications must never abort the hook under errexit)
                  local user_name
                  user_name=$(loginctl list-sessions --no-legend 2>/dev/null | head -1 | awk '{print $3}' || true)

                  if [[ -n "$user_name" ]]; then
                    local uid
                    uid=$(id -u "$user_name" 2>/dev/null || true)
                    if [[ -n "$uid" ]] && [[ -S "/run/user/$uid/bus" ]]; then
                      sudo -u "$user_name" \
                        DISPLAY=:0 \
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        notify-send --urgency="$urgency" "$title" "$message" || true
                    fi
                  fi
                }

                # Function to handle errors
                handle_error() {
                  local step="$1"
                  local exit_code="$2"
                  notify_user "⚠️ GPU Passthrough Failed" "Step: $step (exit $exit_code) — check /var/log/libvirt/gpu-passthrough-hook.log" "critical"
                  exit "$exit_code"
                }

                # Function to run a command and handle errors (captures exit code properly)
                run_or_fail() {
                  local step="$1"
                  shift
                  local exit_code=0
                  "$@" || exit_code=$?
                  if [[ "$exit_code" -ne 0 ]]; then
                    handle_error "$step" "$exit_code"
                  fi
                }

                # Check if VM name matches pattern: NAME-with-gpu-XX
                if [[ "$GUEST_NAME" =~ -with-gpu-([0-9]+)$ ]]; then
                  HUGEPAGES_COUNT="''${BASH_REMATCH[1]}"

                  if [ "$OPERATION" == "prepare" ]; then
                    notify_user "🎮 GPU Passthrough" "Preparing VM: $GUEST_NAME ($HUGEPAGES_COUNT GB hugepages)" "low"

                    echo "[$GUEST_NAME] Preparing GPU passthrough with $HUGEPAGES_COUNT hugepages..."

                    # Hugepages are reserved at boot (hugepages=${toString staticHugepages});
                    # just verify the pool covers this VM
                    FREE_HUGEPAGES=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/free_hugepages)
                    if [[ "$HUGEPAGES_COUNT" -gt "$FREE_HUGEPAGES" ]]; then
                      handle_error "hugepages_pool (need $HUGEPAGES_COUNT, free $FREE_HUGEPAGES of ${toString staticHugepages})" 1
                    fi
                    echo "[$GUEST_NAME] Hugepages available: $FREE_HUGEPAGES free, need $HUGEPAGES_COUNT"

                    # Prevent system sleep during VM operation
                    run_or_fail "start_nosleep" systemctl start libvirt-nosleep.service

                    # Pin host processes to CPUs 0 and 8 BEFORE stopping display manager
                    # This leaves CPUs 1-7 and 9-15 available for the VM
                    echo "[$GUEST_NAME] Pinning host processes to CPUs 0,8..."
                    run_or_fail "pin_user_slice" systemctl set-property --runtime -- user.slice AllowedCPUs=0,8
                    run_or_fail "pin_system_slice" systemctl set-property --runtime -- system.slice AllowedCPUs=0,8
                    run_or_fail "pin_init_scope" systemctl set-property --runtime -- init.scope AllowedCPUs=0,8

                    # Safety net: if a previous release failed, the GPU may still be
                    # on vfio-pci — skip the host-release dance in that case
                    GPU_DRIVER="none"
                    if [[ -e /sys/bus/pci/devices/0000:07:00.0/driver ]]; then
                      GPU_DRIVER=$(basename "$(readlink /sys/bus/pci/devices/0000:07:00.0/driver)")
                    fi

                    if [[ "$GPU_DRIVER" == "vfio-pci" ]]; then
                      echo "[$GUEST_NAME] GPU already bound to vfio-pci, skipping host release steps"
                    else
                      # Stop display manager
                      echo "[$GUEST_NAME] Stopping display manager..."
                      run_or_fail "stop_display_manager" systemctl stop display-manager.service

                      # Wait for display manager to fully release GPU
                      sleep 3

                      # Dynamically unbind all framebuffer consoles
                      echo "[$GUEST_NAME] Unbinding framebuffer consoles..."
                      rm -f /tmp/vfio-bound-consoles
                      for (( i = 0; i < 16; i++ )); do
                        if test -e /sys/class/vtconsole/vtcon"$i"; then
                          if grep -q "frame buffer" /sys/class/vtconsole/vtcon"$i"/name 2>/dev/null; then
                            echo 0 > /sys/class/vtconsole/vtcon"$i"/bind || true
                            echo "$i" >> /tmp/vfio-bound-consoles
                            echo "[$GUEST_NAME] Unbound vtcon$i"
                          fi
                        fi
                      done

                      # Wait until nothing holds the GPU nodes before unloading amdgpu
                      echo "[$GUEST_NAME] Waiting for GPU users to exit..."
                      GPU_BUSY=1
                      for _ in $(seq 1 30); do
                        if ! fuser -s /dev/dri/card* /dev/dri/renderD* 2>/dev/null; then
                          GPU_BUSY=0
                          break
                        fi
                        sleep 1
                      done
                      if [[ "$GPU_BUSY" -ne 0 ]]; then
                        handle_error "gpu_busy_after_wait" 1
                      fi

                      # Unload AMD GPU driver
                      echo "[$GUEST_NAME] Unloading AMD GPU driver..."
                      run_or_fail "unload_amdgpu" modprobe -r amdgpu

                      # Wait for driver to fully unload
                      sleep 2

                      # Detach GPU devices from host (RX 6800 XT via Thunderbolt)
                      echo "[$GUEST_NAME] Detaching GPU devices..."
                      run_or_fail "detach_gpu" virsh nodedev-detach pci_0000_07_00_0
                      run_or_fail "detach_audio" virsh nodedev-detach pci_0000_07_00_1
                    fi

                    # Load VFIO modules immediately after detaching
                    echo "[$GUEST_NAME] Loading VFIO modules..."
                    run_or_fail "load_vfio" modprobe vfio
                    run_or_fail "load_vfio_pci" modprobe vfio_pci
                    run_or_fail "load_vfio_iommu" modprobe vfio_iommu_type1

                    notify_user "✅ GPU Passthrough Ready" "VM $GUEST_NAME is starting" "low"
                    echo "[$GUEST_NAME] GPU passthrough preparation complete"
                    sleep 2
                  fi

                  if [ "$OPERATION" == "release" ]; then
                    notify_user "🔄 GPU Passthrough" "Releasing GPU from VM: $GUEST_NAME" "low"
                    echo "[$GUEST_NAME] Releasing GPU passthrough..."

                    # Unload VFIO modules first
                    echo "[$GUEST_NAME] Unloading VFIO modules..."
                    modprobe -r vfio_pci || true
                    modprobe -r vfio_iommu_type1 || true
                    modprobe -r vfio || true

                    # Wait before resetting GPU
                    sleep 3

                    # PCI secondary bus reset (reset_method = bus; Navi 21 resets
                    # cleanly, no vendor-reset needed). Never reset a device that is
                    # still bound to amdgpu — that wedges the driver (ring timeouts).
                    RELEASE_GPU_DRIVER="none"
                    if [[ -e /sys/bus/pci/devices/0000:07:00.0/driver ]]; then
                      RELEASE_GPU_DRIVER=$(basename "$(readlink /sys/bus/pci/devices/0000:07:00.0/driver)")
                    fi
                    if [[ "$RELEASE_GPU_DRIVER" == "amdgpu" ]]; then
                      echo "[$GUEST_NAME] GPU still bound to amdgpu, skipping bus reset"
                    else
                      echo "[$GUEST_NAME] Triggering GPU reset..."
                      echo 1 > /sys/bus/pci/devices/0000:07:00.0/reset || true
                      sleep 3
                    fi

                    # Reattach GPU devices to host
                    echo "[$GUEST_NAME] Reattaching GPU devices..."
                    virsh nodedev-reattach pci_0000_07_00_0 || true
                    virsh nodedev-reattach pci_0000_07_00_1 || true

                    # Wait for GPU to stabilize after reset before loading driver
                    sleep 10

                    # Reload AMD GPU driver
                    echo "[$GUEST_NAME] Loading AMD GPU driver..."
                    modprobe amdgpu || true

                    # Wait for driver to initialize
                    sleep 5

                    # Rebind framebuffer consoles that were originally bound
                    echo "[$GUEST_NAME] Rebinding framebuffer consoles..."
                    if test -e /tmp/vfio-bound-consoles; then
                      while read -r consoleNumber; do
                        if test -e /sys/class/vtconsole/vtcon"$consoleNumber"; then
                          if grep -q "frame buffer" /sys/class/vtconsole/vtcon"$consoleNumber"/name 2>/dev/null; then
                            echo 1 > /sys/class/vtconsole/vtcon"$consoleNumber"/bind || true
                            echo "[$GUEST_NAME] Rebound vtcon$consoleNumber"
                          fi
                        fi
                      done < /tmp/vfio-bound-consoles
                      rm -f /tmp/vfio-bound-consoles
                    fi

                    # Restart display manager (restart, not start: after a skipped
                    # prepare GDM may still be running against a vanished GPU and
                    # must be forced to re-initialize)
                    echo "[$GUEST_NAME] Restarting display manager..."
                    systemctl restart display-manager.service || true

                    # Restore CPU allocation to all cores (0-15)
                    echo "[$GUEST_NAME] Restoring CPU allocation..."
                    systemctl set-property --runtime -- user.slice AllowedCPUs=0-15 || true
                    systemctl set-property --runtime -- system.slice AllowedCPUs=0-15 || true
                    systemctl set-property --runtime -- init.scope AllowedCPUs=0-15 || true

                    # Allow system sleep again
                    systemctl stop libvirt-nosleep.service || true

                    notify_user "✅ GPU Released" "Display manager restored" "low"
                    echo "[$GUEST_NAME] GPU passthrough release complete"
                    sleep 2
                  fi
                fi
              '';
            }
          );
        };

        # Service to inhibit sleep while VM is running
        systemd.services.libvirt-nosleep = {
          description = "Inhibit sleep while libvirt VM with GPU passthrough is running";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=sleep --why=\"Libvirt GPU passthrough VM is running\" --who=libvirt --mode=block sleep infinity";
          };
        };
      };
    };
  };
}
