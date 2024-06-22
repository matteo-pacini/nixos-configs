{ lib, ... }:
let
  diskNumbers = lib.lists.range 0 9;
  snapraidDataDisksName = builtins.map (i: "d${toString i}") diskNumbers;
in
{
  services.snapraid = {
    enable = true;
    dataDisks = lib.genAttrs snapraidDataDisksName (d: "/mnt/disk${lib.strings.removePrefix "d" d}");
    contentFiles = builtins.map (i: "/mnt/disk${toString i}/snapraid.content") diskNumbers;
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
      "/mnt/parity2/snapraid.2-parity"
    ];
    exclude = [
      "*.unrecoverable"
      "/tmp/"
      "/lost+found/"
    ];
    touchBeforeSync = true;
  };
}
