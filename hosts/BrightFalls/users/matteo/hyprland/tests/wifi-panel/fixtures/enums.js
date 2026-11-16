// Copied by hand from Quickshell 0.3.2's src/network/enums.hpp (the pinned
// source: nix eval --raw .#nixosConfigurations.BrightFalls.pkgs.quickshell.src.outPath).
// Update it when Quickshell is bumped; the test fails if wifi.js does not
// know a name here.
module.exports = {
    WifiSecurityType: ["Wpa3SuiteB192", "Sae", "Wpa2Eap", "Wpa2Psk", "WpaEap", "WpaPsk", "StaticWep", "DynamicWep", "Leap", "Owe", "Open", "Unknown"],
    ConnectionFailReason: ["Unknown", "NoSecrets", "WifiClientDisconnected", "WifiClientFailed", "WifiAuthTimeout", "WifiNetworkLost"],
    ConnectionState: ["Unknown", "Connecting", "Connected", "Disconnecting", "Disconnected"],
    NetworkConnectivity: ["Unknown", "None", "Portal", "Limited", "Full"]
};
