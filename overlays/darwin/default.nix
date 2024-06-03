final: prev: {
  firefox-app = prev.callPackage ../../packages/darwin/firefox-app.nix { };
  needle = prev.callPackage ../../packages/darwin/needle { };
  swiftlint = prev.callPackage ../../packages/darwin/swiftlint.nix { };
}
