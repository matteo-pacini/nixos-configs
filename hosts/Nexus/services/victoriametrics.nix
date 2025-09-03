{ ... }:
{

  services.victoriametrics = {
    enable = true;
    listenAddress = "0.0.0.0:8428";
    retentionPeriod = "100y";
  };

  services.victorialogs.enable = true;

}
