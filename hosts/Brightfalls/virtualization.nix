{
  lib,
  pkgs,
  config,
  isVM,
  ...
}:
let
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
    ];

    text = ''
      set -euo pipefail

      # Usage check
      if [ $# -lt 1 ]; then
        echo "Usage: vfio-collect-logs <vm-name> [output-dir]"
        echo "Example: vfio-collect-logs win11-with-gpu"
        echo "         vfio-collect-logs win11-with-gpu /tmp"
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

        echo "--- GPU PCI Devices (0a:00.x) ---"
        lspci -nnk -s 0a:00 2>/dev/null || echo "Failed to get GPU PCI info"
        echo ""

        echo "--- IOMMU Groups ---"
        for d in /sys/kernel/iommu_groups/*/devices/*; do
          if [ -e "$d" ]; then
            n="''${d#*/iommu_groups/}"; n="''${n%%/*}"
            printf 'IOMMU Group %s: ' "$n"
            lspci -nns "''${d##*/}" 2>/dev/null || echo "''${d##*/}"
          fi
        done 2>/dev/null | grep -E "(0a:00|vfio|VGA)" || echo "No relevant IOMMU groups found"
        echo ""

        echo "--- GPU Reset Method ---"
        cat /sys/bus/pci/devices/0000:0a:00.0/reset_method 2>/dev/null || echo "reset_method not available"
        echo ""

        echo "--- Loaded GPU/VFIO Modules ---"
        lsmod | grep -E "(amdgpu|vfio|vendor.reset|kvm)" || echo "No relevant modules loaded"
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

        # --- Section 4: Kernel Logs (Current Boot) ---
        echo "========================================================================"
        echo "SECTION 4: KERNEL LOGS - CURRENT BOOT"
        echo "========================================================================"
        echo ""

        echo "--- dmesg: GPU/VFIO related (current boot) ---"
        dmesg 2>/dev/null | grep -iE "(amdgpu|vfio|iommu|vendor.reset|pci 0000:0a|gpu|drm|reset)" | tail -n 300 || echo "No relevant dmesg entries"
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
        journalctl -k -b -1 --no-pager 2>/dev/null | grep -iE "(amdgpu|vfio|iommu|vendor.reset|pci 0000:0a|gpu|drm|reset)" | tail -n 300 || echo "No previous boot kernel logs available"
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
        ps aux | grep -E "[q]emu" || echo "No QEMU processes running"
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
  specialisation."VFIO".configuration = lib.mkIf (!isVM) {

    system.nixos.tags = [ "with-vfio" ];

    # Add debug log collection script to system packages
    environment.systemPackages = [ vfio-collect-logs ];

    # Disable GPU-using services and Linux gaming optimizations in VFIO mode
    # (gaming will be done in the VM, not on the Linux host)
    services.sunshine.enable = lib.mkForce false;
    services.lact.enable = lib.mkForce false;
    hardware.amdgpu.overdrive.enable = lib.mkForce false;

    # vendor-reset module for proper AMD GPU reset between VM uses
    # This helps prevent blank screen issues on second VM boot
    boot.extraModulePackages = [ config.boot.kernelPackages.vendor-reset ];

    # Load vendor-reset early, before amdgpu
    boot.kernelModules = [ "vendor-reset" ];
    # Make VBIOS available at runtime for GPU passthrough
    systemd.tmpfiles.rules = [
      "L+ /run/libvirt/vbios/brightfalls_6800xt.rom - - - - ${./../../extra/brightfalls_6800xt_vbios}"
    ];

    boot.kernelParams = [
      # Enable AMD IOMMU (Input-Output Memory Management Unit) for hardware virtualization and device isolation
      "amd_iommu=on"

      # Set IOMMU to passthrough mode: only isolate devices assigned to VMs, better performance for host
      "iommu=pt"

      # Allow interrupt remapping for devices without proper IOMMU interrupt remapping support
      "vfio_iommu_type1.allow_unsafe_interrupts=1"

      # Ignore MSR access violations to prevent VM crashes (required for some AMD CPUs)
      "kvm.ignore_msrs=1"

      # Configure 20x1GB hugepages for better VM memory performance
      "default_hugepagesz=1G"
      "hugepagesz=1G"
      "hugepages=20"
    ];

    virtualisation.spiceUSBRedirection.enable = true;

    users.extraUsers.matteo.extraGroups = [
      "kvm"
      "libvirtd"
    ];

    programs.virt-manager.enable = true;
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };

      # Enhanced logging for debugging
      extraConfig = ''
        log_filters="3:qemu 1:libvirt"
        log_outputs="2:file:/var/log/libvirt/libvirtd.log"
      '';

      # GPU passthrough hook for VMs with names ending in "-with-gpu"
      hooks.qemu = {
        "gpu-passthrough" = lib.getExe (
          pkgs.writeShellApplication {
            name = "qemu-gpu-passthrough-hook";

            runtimeInputs = with pkgs; [
              libvirt
              systemd
              kmod
              gawk
            ];

            text = ''
              set -x  # Enable debug tracing

              GUEST_NAME="$1"
              OPERATION="$2"

              # Only run for VMs with names ending in "-with-gpu"
              if [[ "$GUEST_NAME" == *-with-gpu ]]; then
                if [ "$OPERATION" == "prepare" ]; then
                  echo "[$GUEST_NAME] Preparing GPU passthrough..."

                  # Prevent system sleep during VM operation
                  systemctl start libvirt-sleep

                  # Pin host processes to CPUs 0 and 8 BEFORE stopping display manager
                  # This leaves CPUs 1-7 and 9-15 available for the VM
                  echo "[$GUEST_NAME] Pinning host processes to CPUs 0,8..."
                  systemctl set-property --runtime -- user.slice AllowedCPUs=0,8
                  systemctl set-property --runtime -- system.slice AllowedCPUs=0,8
                  systemctl set-property --runtime -- init.scope AllowedCPUs=0,8

                  # Stop display manager
                  echo "[$GUEST_NAME] Stopping display manager..."
                  systemctl stop display-manager.service

                  # Wait for display manager to fully release GPU
                  sleep 3

                  # Dynamically unbind all framebuffer consoles
                  echo "[$GUEST_NAME] Unbinding framebuffer consoles..."
                  rm -f /tmp/vfio-bound-consoles
                  for (( i = 0; i < 16; i++ )); do
                    if test -x /sys/class/vtconsole/vtcon"$i"; then
                      if grep -q "frame buffer" /sys/class/vtconsole/vtcon"$i"/name 2>/dev/null; then
                        echo 0 > /sys/class/vtconsole/vtcon"$i"/bind || true
                        echo "$i" >> /tmp/vfio-bound-consoles
                        echo "[$GUEST_NAME] Unbound vtcon$i"
                      fi
                    fi
                  done

                  # NOTE: EFI framebuffer unbind is SKIPPED for AMD 6000 series (causes issues)
                  # See: https://github.com/QaidVoid/Complete-Single-GPU-Passthrough
                  # echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind || true

                  # Wait for consoles to unbind
                  sleep 2

                  # Unload AMD GPU driver
                  echo "[$GUEST_NAME] Unloading AMD GPU driver..."
                  modprobe -r amdgpu

                  # Wait for driver to fully unload
                  sleep 2

                  # Detach GPU devices from host (AMD RX 6800/6800 XT / 6900 XT)
                  echo "[$GUEST_NAME] Detaching GPU devices..."
                  virsh nodedev-detach pci_0000_0a_00_0  # GPU
                  virsh nodedev-detach pci_0000_0a_00_1  # Audio

                  # Load VFIO modules immediately after detaching
                  echo "[$GUEST_NAME] Loading VFIO modules..."
                  modprobe vfio
                  modprobe vfio_pci
                  modprobe vfio_iommu_type1

                  echo "[$GUEST_NAME] GPU passthrough preparation complete"
                fi

                if [ "$OPERATION" == "release" ]; then
                  echo "[$GUEST_NAME] Releasing GPU passthrough..."

                  # Unload VFIO modules first
                  echo "[$GUEST_NAME] Unloading VFIO modules..."
                  modprobe -r vfio_pci
                  modprobe -r vfio_iommu_type1
                  modprobe -r vfio

                  # Wait before resetting GPU
                  sleep 3

                  # Trigger GPU reset via vendor-reset module
                  # Only reset the GPU device (0a:00.0), not the audio device (0a:00.1)
                  # On kernel 6.x, vendor-reset hooks directly into the reset infrastructure
                  echo "[$GUEST_NAME] Triggering GPU reset via vendor-reset..."
                  echo 1 > /sys/bus/pci/devices/0000:0a:00.0/reset || true
                  sleep 3

                  # Reattach GPU devices to host
                  echo "[$GUEST_NAME] Reattaching GPU devices..."
                  virsh nodedev-reattach pci_0000_0a_00_0
                  virsh nodedev-reattach pci_0000_0a_00_1

                  # Wait for GPU to stabilize after reset before loading driver
                  sleep 10

                  # Reload AMD GPU driver
                  echo "[$GUEST_NAME] Loading AMD GPU driver..."
                  modprobe amdgpu

                  # Wait for driver to initialize
                  sleep 5

                  # NOTE: EFI framebuffer rebind is SKIPPED for AMD 6000 series (causes issues)
                  # echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind || true

                  # Rebind framebuffer consoles that were originally bound
                  echo "[$GUEST_NAME] Rebinding framebuffer consoles..."
                  if test -e /tmp/vfio-bound-consoles; then
                    while read -r consoleNumber; do
                      if test -x /sys/class/vtconsole/vtcon"$consoleNumber"; then
                        if grep -q "frame buffer" /sys/class/vtconsole/vtcon"$consoleNumber"/name 2>/dev/null; then
                          echo 1 > /sys/class/vtconsole/vtcon"$consoleNumber"/bind || true
                          echo "[$GUEST_NAME] Rebound vtcon$consoleNumber"
                        fi
                      fi
                    done < /tmp/vfio-bound-consoles
                    rm -f /tmp/vfio-bound-consoles
                  fi

                  # Restart display manager
                  echo "[$GUEST_NAME] Starting display manager..."
                  systemctl start display-manager.service

                  # Restore CPU allocation to all cores (0-15)
                  echo "[$GUEST_NAME] Restoring CPU allocation..."
                  systemctl set-property --runtime -- user.slice AllowedCPUs=0-15
                  systemctl set-property --runtime -- system.slice AllowedCPUs=0-15
                  systemctl set-property --runtime -- init.scope AllowedCPUs=0-15

                  # Allow system sleep again
                  systemctl stop libvirt-sleep

                  echo "[$GUEST_NAME] GPU passthrough release complete"
                fi
              fi
            '';
          }
        );
      };
    };
  };

  systemd.services.libvirt-sleep = {
    enable = true;
    serviceConfig = {
      ExecStart = ''systemd-inhibit --what=sleep --why="Libvirt domain \"%i\" is running" --who=%U --mode=block sleep infinity'';
    };
  };

}
