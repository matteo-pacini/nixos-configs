{
  pkgs,
  lib,
  config,
  isVM,
  ...
}:
{
  # Basic virtualization support (always available when not a VM)
  #
  # USB Controllers (for reference):
  # - Back USB ports: c8:00.3 (IOMMU Group 26)

  virtualisation.spiceUSBRedirection.enable = lib.mkIf (!isVM) true;

  users.extraUsers.matteo.extraGroups = lib.mkIf (!isVM) [
    "kvm"
    "libvirtd"
  ];

  programs.virt-manager.enable = lib.mkIf (!isVM) true;

  virtualisation.libvirtd = lib.mkIf (!isVM) {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # VFIO specialisation for GPU passthrough
  # Boot into "BrightFalls (VFIO)" to enable GPU passthrough
  # VMs with names matching "NAME-with-gpu-XX" will trigger GPU passthrough
  # where XX is the number of 1GB hugepages to allocate
  specialisation = lib.mkIf (!isVM) {
    VFIO = {
      inheritParentConfig = true;
      configuration = {
        system.nixos.tags = [ "with-vfio" ];

        # Disable services that conflict with GPU passthrough
        services.sunshine.enable = lib.mkForce false;
        services.lact.enable = lib.mkForce false;
        hardware.amdgpu.overdrive.enable = lib.mkForce false;

        # vendor-reset module for proper AMD GPU reset between VM uses
        # Navi 21 (6800 XT) generally doesn't need it on kernel 6.x, but harmless to have
        boot.extraModulePackages = [ config.boot.kernelPackages.vendor-reset ];
        boot.kernelModules = [ "vendor-reset" ];

        # Kernel params for IOMMU (required for GPU passthrough)
        boot.kernelParams = [
          # Enable AMD IOMMU for hardware virtualization and device isolation
          "amd_iommu=on"
          # Passthrough mode: only isolate devices assigned to VMs, better performance for host
          "iommu=pt"
          # Allow interrupt remapping for devices without proper IOMMU support
          "vfio_iommu_type1.allow_unsafe_interrupts=1"
          # Ignore MSR access violations to prevent VM crashes (required for some AMD CPUs)
          "kvm.ignore_msrs=1"
          # Set default hugepage size to 1GB (allocation done dynamically in QEMU hook)
          "default_hugepagesz=1G"
          "hugepagesz=1G"
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
                sudo
              ];

              text = ''
                set -x  # Enable debug tracing

                GUEST_NAME="$1"
                OPERATION="$2"

                # Function to send notification to logged-in user
                notify_user() {
                  local title="$1"
                  local message="$2"
                  local urgency="''${3:-normal}"  # normal, low, critical

                  # Find the first logged-in graphical session user
                  local user_name
                  user_name=$(loginctl list-sessions --no-legend 2>/dev/null | head -1 | awk '{print $3}')

                  if [[ -n "$user_name" ]]; then
                    local uid
                    uid=$(id -u "$user_name" 2>/dev/null)
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
                  notify_user "⚠️ GPU Passthrough Failed" "Step: $step\nExit code: $exit_code\nCheck /var/log/libvirt/libvirtd.log" "critical"
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

                    # Allocate hugepages dynamically with retries
                    echo "[$GUEST_NAME] Allocating $HUGEPAGES_COUNT x 1GB hugepages..."

                    MAX_RETRIES=10
                    ALLOCATED=0

                    for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
                      echo "[$GUEST_NAME] Hugepages allocation attempt $attempt/$MAX_RETRIES..."

                      # Drop caches and compact memory to maximize chance of allocation
                      sync
                      echo 3 > /proc/sys/vm/drop_caches || true
                      echo 1 > /proc/sys/vm/compact_memory || true

                      # Wait for compaction to complete (longer on later attempts)
                      sleep $((attempt + 2))

                      # Attempt allocation
                      echo "$HUGEPAGES_COUNT" > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages || true

                      # Check result
                      ALLOCATED=$(cat /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages)
                      echo "[$GUEST_NAME] Attempt $attempt: allocated $ALLOCATED / $HUGEPAGES_COUNT hugepages"

                      if [[ "$ALLOCATED" -ge "$HUGEPAGES_COUNT" ]]; then
                        echo "[$GUEST_NAME] Hugepages allocation successful!"
                        break
                      fi

                      if [[ "$attempt" -lt "$MAX_RETRIES" ]]; then
                        echo "[$GUEST_NAME] Allocation incomplete, retrying..."
                        # Reset hugepages before retry
                        echo 0 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages || true
                        sleep 2
                      fi
                    done

                    # Final verification after all retries
                    if [[ "$ALLOCATED" -lt "$HUGEPAGES_COUNT" ]]; then
                      # Reset hugepages on failure
                      echo 0 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages || true
                      handle_error "hugepages_verify (got $ALLOCATED, wanted $HUGEPAGES_COUNT after $MAX_RETRIES attempts)" 1
                    fi
                    echo "[$GUEST_NAME] Allocated $ALLOCATED x 1GB hugepages"

                    # Prevent system sleep during VM operation
                    run_or_fail "start_nosleep" systemctl start libvirt-nosleep.service

                    # Pin host processes to CPUs 0 and 8 BEFORE stopping display manager
                    # This leaves CPUs 1-7 and 9-15 available for the VM
                    echo "[$GUEST_NAME] Pinning host processes to CPUs 0,8..."
                    run_or_fail "pin_user_slice" systemctl set-property --runtime -- user.slice AllowedCPUs=0,8
                    run_or_fail "pin_system_slice" systemctl set-property --runtime -- system.slice AllowedCPUs=0,8
                    run_or_fail "pin_init_scope" systemctl set-property --runtime -- init.scope AllowedCPUs=0,8

                    # Stop display manager
                    echo "[$GUEST_NAME] Stopping display manager..."
                    run_or_fail "stop_display_manager" systemctl stop display-manager.service

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

                    # Wait for consoles to unbind
                    sleep 2

                    # Unload AMD GPU driver
                    echo "[$GUEST_NAME] Unloading AMD GPU driver..."
                    run_or_fail "unload_amdgpu" modprobe -r amdgpu

                    # Wait for driver to fully unload
                    sleep 2

                    # Detach GPU devices from host (RX 6800 XT via Thunderbolt)
                    echo "[$GUEST_NAME] Detaching GPU devices..."
                    run_or_fail "detach_gpu" virsh nodedev-detach pci_0000_07_00_0
                    run_or_fail "detach_audio" virsh nodedev-detach pci_0000_07_00_1

                    # Load VFIO modules immediately after detaching
                    echo "[$GUEST_NAME] Loading VFIO modules..."
                    run_or_fail "load_vfio" modprobe vfio
                    run_or_fail "load_vfio_pci" modprobe vfio_pci
                    run_or_fail "load_vfio_iommu" modprobe vfio_iommu_type1

                    notify_user "✅ GPU Passthrough Ready" "VM $GUEST_NAME is starting" "low"
                    echo "[$GUEST_NAME] GPU passthrough preparation complete"
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

                    # Trigger GPU reset via vendor-reset module
                    echo "[$GUEST_NAME] Triggering GPU reset via vendor-reset..."
                    echo 1 > /sys/bus/pci/devices/0000:07:00.0/reset || true
                    sleep 3

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
                    systemctl start display-manager.service || true

                    # Restore CPU allocation to all cores (0-15)
                    echo "[$GUEST_NAME] Restoring CPU allocation..."
                    systemctl set-property --runtime -- user.slice AllowedCPUs=0-15 || true
                    systemctl set-property --runtime -- system.slice AllowedCPUs=0-15 || true
                    systemctl set-property --runtime -- init.scope AllowedCPUs=0-15 || true

                    # Free hugepages
                    echo "[$GUEST_NAME] Freeing hugepages..."
                    echo 0 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages || true

                    # Allow system sleep again
                    systemctl stop libvirt-nosleep.service || true

                    notify_user "✅ GPU Released" "Display manager restored" "low"
                    echo "[$GUEST_NAME] GPU passthrough release complete"
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
