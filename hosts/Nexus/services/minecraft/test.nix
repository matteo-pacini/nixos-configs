# NixOS VM test for the All of Create server: boots the pack under the real
# hardened unit, checks the console FIFO, then stops it and expects a clean
# save. Not wired into the flake or CI; run it from the repo root with:
#
#   nix build -L --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest ./hosts/Nexus/services/minecraft/test.nix'
#
# Needs KVM and ~13 GB of free RAM; downloads the server pack and NeoForge
# libraries on first run.
{
  name = "minecraft-all-of-create";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ ./default.nix ];

      virtualisation = {
        memorySize = 12288;
        cores = 4;
        diskSize = 8192;
      };

      # Production flags with a smaller heap so the VM fits; -Xlog:gc+init
      # makes ZGC report whether transparent huge pages took effect.
      services.minecraft-server.jvmOpts = lib.mkForce (
        lib.concatStringsSep " " [
          "-Xms5G"
          "-Xmx5G"
          "-XX:+UseZGC"
          "-XX:+ZGenerational"
          "-XX:+AlwaysPreTouch"
          "-XX:+UseTransparentHugePages"
          "-XX:+DisableExplicitGC"
          "-XX:+PerfDisableSharedMem"
          "-Dlog4j2.formatMsgNoLookups=true"
          "-Xlog:gc+init"
        ]
      );
    };

  testScript = ''
    machine.wait_for_unit("minecraft-server.service")
    machine.wait_until_succeeds("journalctl -u minecraft-server | grep -q 'Done ('", timeout=900)
    machine.wait_for_open_port(25565)

    with subtest("transparent huge pages back the heap"):
        machine.succeed("grep -q '\\[advise\\]' /sys/kernel/mm/transparent_hugepage/shmem_enabled")
        machine.succeed("journalctl -u minecraft-server | grep -q 'Large Page Support: Enabled (Transparent)'")

    with subtest("data dir layout"):
        machine.succeed("test \"$(stat -c '%U %a' /var/lib/minecraft)\" = 'minecraft 700'")
        machine.succeed("test -d /var/lib/minecraft/mods && test ! -L /var/lib/minecraft/mods")
        machine.succeed("test -f /var/lib/minecraft/.pack-version")
        machine.succeed("grep -qx 'white-list=false' /var/lib/minecraft/server.properties")

    with subtest("console FIFO reaches the server"):
        machine.succeed("echo 'say hello from test' > /run/minecraft-server.stdin")
        machine.wait_until_succeeds("journalctl -u minecraft-server | grep -q 'hello from test'")

    with subtest("stop saves the world without being killed"):
        machine.succeed("systemctl stop minecraft-server")
        machine.succeed("journalctl -u minecraft-server | grep -q 'All chunks are saved'")
        machine.fail("journalctl -u minecraft-server | grep -E 'Killing process|timed out'")
        machine.succeed("test -f /var/lib/minecraft/world/level.dat")

    with subtest("no seccomp denials"):
        machine.fail("journalctl -u minecraft-server | grep -E 'Bad system call|SIGSYS'")
  '';
}
