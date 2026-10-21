{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.minecraft-server;
  aoc = pkgs.callPackage ./all-of-create.nix { };

  # Node 0's CPUs (lscpu: "NUMA node0 CPU(s): 0-70:2"). The tick loop is
  # single-threaded and latency-bound; keeping its threads and heap on one
  # socket avoids cross-QPI memory accesses on the dual E5-2697 v4.
  numaNode0Cpus = map (i: toString (i * 2)) (lib.range 0 35);
in
{
  # nixpkgs' module brings the dedicated user, the stdin FIFO console
  # (/run/minecraft-server.stdin) and a graceful "stop" on ExecStop; the
  # package is swapped for a NeoForge launcher.
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = aoc.launcher;
    dataDir = "/var/lib/minecraft";
    # Ports are opened in ../../networking.nix (LAN + tailnet only).
    openFirewall = false;

    # server.properties is rewritten from here on every start: change it
    # here, not in-game.
    declarative = true;
    serverProperties = {
      # Directory under dataDir. To import a world, copy the save folder
      # there and set this to its name.
      level-name = "world";
      server-port = 25565;
      motd = "All of Create";
      difficulty = "easy";
      gamemode = "survival";
      max-players = 10;
      online-mode = true;
      # No whitelist: the firewall already limits joins to the LAN and tailnet.
      white-list = false;
      enforce-whitelist = false;
      # Pack defaults: jetpacks and contraptions trip the flying-kick check,
      # and heavy modded ticks need a longer watchdog than vanilla's 60 s.
      allow-flight = true;
      max-tick-time = 120000;
      view-distance = 10;
      spawn-protection = 16;
      enable-command-block = true;
      enable-rcon = false;
      enable-query = false;
      sync-chunk-writes = true;
    };

    # Heap: 10 GB for ~180 server-side mods with a handful of players; Nexus
    # has ~85 GB free, so it is sized for headroom, not squeezed.
    # Generational ZGC: sub-millisecond pauses, and the concurrent GC threads
    # it needs are cheap on 72 threads. ZGenerational is still opt-in on 21.
    # Xms = Xmx + AlwaysPreTouch: the heap is committed once at boot rather
    # than grown mid-game; on a host this size that is a fixed 10 GB, not a
    # risk to neighbours.
    # UseTransparentHugePages madvise()s only the JVM's own heap. ZGC backs
    # the heap with shmem, so it also needs shmem_enabled=advise (set below);
    # the anonymous-memory THP mode is already madvise.
    jvmOpts = lib.concatStringsSep " " [
      "-Xms10G"
      "-Xmx10G"
      "-XX:+UseZGC"
      "-XX:+ZGenerational"
      "-XX:+AlwaysPreTouch"
      "-XX:+UseTransparentHugePages"
      "-XX:+DisableExplicitGC"
      "-XX:+PerfDisableSharedMem"
      "-Dlog4j2.formatMsgNoLookups=true"
    ];
  };

  # Kernel default is "never". "advise" only affects shmem regions that ask
  # via MADV_HUGEPAGE, so other services' shared memory is unchanged.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise"
  ];

  systemd.services.minecraft-server = {
    # Runs before the upstream preStart (eula, server.properties).
    # defaultconfigs/ is only read, so it points straight at the store.
    # mods/ is copied: Sinytra Connector rejects its own jar when mods/ is a
    # store symlink ("is not a valid mod file"). config/ is rewritten by mods
    # at runtime. Both are recopied only when the pack changes, which keeps
    # local config edits across restarts but not across pack upgrades.
    preStart = lib.mkBefore ''
      if [ -e defaultconfigs ] && [ ! -L defaultconfigs ]; then rm -rf defaultconfigs; fi
      ln -sfn ${aoc.pack}/defaultconfigs defaultconfigs
      ln -sf ${aoc.pack}/server-icon.png server-icon.png

      if [ "$(cat .pack-version 2>/dev/null)" != "${aoc.pack}" ]; then
        rm -rf mods
        cp -r --no-preserve=mode,ownership ${aoc.pack}/mods mods
        mkdir -p config
        cp -rf --no-preserve=mode,ownership ${aoc.pack}/config/. config/
        echo "${aoc.pack}" > .pack-version
      fi
    '';

    serviceConfig = {
      # Saving a large modded world on "stop" can outlast the 90 s default.
      TimeoutStopSec = "5min";
      # Upstream restarts always; don't re-touch a 10 GB heap in a tight loop.
      RestartSec = "30s";

      StateDirectory = "minecraft";
      StateDirectoryMode = "0700";
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      RemoveIPC = true;
      # No MemoryDenyWriteExecute: the JIT needs W+X pages.
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
      SystemCallErrorNumber = "EPERM";

      # Heap plus metaspace, code cache and mod native buffers; a cap so a
      # leak takes down the game, not Home Assistant.
      MemoryMax = "16G";
      CPUAffinity = lib.concatStringsSep " " numaNode0Cpus;
      NUMAPolicy = "preferred";
      NUMAMask = "0";
    };
  };
}
