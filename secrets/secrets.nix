let
  nightSprings = "age19vdy03ry5p2vgv8jxuj8v0mzgez5ddqe479597n46vz0day3mf2qq8tm9f";
  nexus = "age1vny8hulfcwmr2gak8pp26cccxsple8z5tvvprg32ypap7v7cjfxqsza4mz";
in
{
  "nexus/disk0.age".publicKeys = [ nexus ];
  "nexus/disk1.age".publicKeys = [ nexus ];
  "nexus/disk2.age".publicKeys = [ nexus ];
  "nexus/disk3.age".publicKeys = [ nexus ];
  "nexus/disk4.age".publicKeys = [ nexus ];
  "nexus/disk5.age".publicKeys = [ nexus ];
  "nexus/disk6.age".publicKeys = [ nexus ];
  "nexus/disk7.age".publicKeys = [ nexus ];
  "nexus/disk8.age".publicKeys = [ nexus ];
  "nexus/disk9.age".publicKeys = [ nexus ];
}
