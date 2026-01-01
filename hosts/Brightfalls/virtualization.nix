{
  lib,
  pkgs,
  isVM,
  ...
}:
{
  specialisation."VFIO".configuration = lib.mkIf (!isVM) {

    system.nixos.tags = [ "with-vfio" ];

    # Disable GPU-using services in VFIO mode to prevent conflicts
    services.sunshine.enable = lib.mkForce false;
    services.lact.enable = lib.mkForce false;

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

              # Redirect all output to log file
              exec 19>>"/home/matteo/''${GUEST_NAME}.log"
              echo "[$(date)] [$OPERATION] GPU passthrough hook started for $GUEST_NAME" >&19
              BASH_XTRACEFD=19

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

                  # Wait before reattaching GPU
                  sleep 2

                  # Reattach GPU devices to host
                  echo "[$GUEST_NAME] Reattaching GPU devices..."
                  virsh nodedev-reattach pci_0000_0a_00_0
                  virsh nodedev-reattach pci_0000_0a_00_1

                  # Wait for devices to reattach
                  sleep 2

                  # Reload AMD GPU driver IMMEDIATELY after reattaching
                  echo "[$GUEST_NAME] Loading AMD GPU driver..."
                  modprobe amdgpu

                  # Wait for driver to initialize
                  sleep 3

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
