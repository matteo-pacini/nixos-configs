{
  lib,
  config,
  pkgs,
  modulesPath,
  ...
}:
{

  boot.swraid = {
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md/array metadata=1.2 name=nixos:array UUID=ea2caefe:f8f04158:af8eacaa:8b5984b4
    '';
  };

  environment.etc.crypttab.text = ''
    disk0   UUID=acc41b71-316b-45d8-8f0b-7451f07704e5   ${config.age.secrets."nexus/disk0".path}
    disk1   UUID=10b7a53d-00d7-44b8-a939-81e5e97cb39b   ${config.age.secrets."nexus/disk1".path}
    disk2   UUID=5f612cb9-5386-4bad-9ac7-63cc5297886a   ${config.age.secrets."nexus/disk2".path}
    disk3   UUID=46707d5b-8251-4b0d-b1b1-5342e5b869cc   ${config.age.secrets."nexus/disk3".path}
    disk4   UUID=468f45f0-1ec1-4345-ac77-54bb16a5c064   ${config.age.secrets."nexus/disk4".path}
    disk5   UUID=3af3cf56-3141-422b-9de3-06b0849bf7ca   ${config.age.secrets."nexus/disk5".path}
    disk6   UUID=bea58b71-f5e1-4406-8312-70c8ee850536   ${config.age.secrets."nexus/disk6".path}
    disk7   UUID=5c754299-f3d7-42ad-9156-35c97c70a269   ${config.age.secrets."nexus/disk7".path}
    disk8   UUID=58caf63b-4142-45ab-8392-ba02cc4a86f3   ${config.age.secrets."nexus/disk8".path}
    disk9   UUID=293952af-363d-4ca1-bb74-23e22d67b393   ${config.age.secrets."nexus/disk9".path}
  '';
}
