final: prev: {
  xcodes-app = prev.callPackage ../../packages/darwin/xcodes-app.nix {};
  radiogogo = prev.callPackage ../../packages/radiogogo.nix {};
}