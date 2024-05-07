final: prev: {
  fixed-unstable-mangohud = prev.unstable.mangohud.overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [
        ../patches/mangohud/0001-reset_fps_metrics-check-that-metrics-is-inited-first.patch
      ];
  });
}
