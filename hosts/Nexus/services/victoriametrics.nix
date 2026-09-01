{ ... }:
{
  # Long-term metrics archive for Home Assistant.
  #
  # HA's Postgres recorder costs roughly 60 MB/day for raw states; the same
  # series in VictoriaMetrics cost about 0.7 MB/day. The recorder still backs
  # the UI (history, logbook, more-info graphs) and keeps long-term statistics
  # forever, so this is a parallel archive, not a replacement — see the
  # `influxdb` block and the short `purge_keep_days` in home-assistant.nix.
  services.victoriametrics = {
    enable = true;

    # Loopback only. Home Assistant writes and Grafana reads over localhost;
    # nothing external should reach the unauthenticated write endpoint.
    listenAddress = "127.0.0.1:8428";

    # Mandatory. Upstream defaults to one month and prunes older partitions on
    # first compaction, which would silently destroy the archive this exists
    # to keep.
    retentionPeriod = "100y";
  };
}
