# virglrenderer with upstream's Venus patches (build_runtime.py virgl()).
# nixpkgs' build is the same 1.3.0 release upstream pins, with Venus already
# on; QEMU links it and the launcher runs its virgl_render_server.
{ virglrenderer, legionSource }:
assert virglrenderer.version == "1.3.0";
virglrenderer.overrideAttrs (old: {
  pname = "legion-kvm-virglrenderer";
  patches = (old.patches or [ ]) ++ [
    "${legionSource.src}/patches/virgl-venus-sync-fd-experimental.patch"
    "${legionSource.src}/patches/virgl-venus-ring-poll-experimental.patch"
  ];
})
