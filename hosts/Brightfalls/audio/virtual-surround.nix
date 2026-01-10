# Virtual 7.1 Surround Sound for Headphones
#
# This module creates a virtual 7.1 surround sound sink using PipeWire's
# filter-chain with SOFA (Spatially Oriented Format for Acoustics) spatializer.
#
# How it works:
# - Takes 7.1 surround input (FL, FR, FC, LFE, RL, RR, SL, SR)
# - Applies HRTF (Head-Related Transfer Function) processing using a SOFA file
# - Outputs binaural stereo to your headphones
#
# Usage:
# - Select "Virtual Surround 7.1" in GNOME Sound Settings when you want spatial audio
# - Use your normal output device for stereo music (no processing)
#
# The SOFA file used is from the ARI (Acoustics Research Institute) database.
# It provides a generic HRTF that works well for most people.
{
  pkgs,
  lib,
  isVM,
  ...
}:
let
  # Download the SOFA file from ARI database
  # This is a diffuse-field equalized HRTF that works well for most listeners
  sofaFile = pkgs.fetchurl {
    url = "https://sofacoustics.org/data/database/ari/dtf_nh2.sofa";
    hash = "sha256-Mt0RjeibQRnk6Gk+Ova9X0aCTn2W2fd8RdXoHXi276k=";
  };
  # Helper to create a spatializer node
  mkSpatializer = name: azimuth: elevation: {
    type = "sofa";
    label = "spatializer";
    inherit name;
    config.filename = sofaFile;
    control = {
      Azimuth = azimuth;
      Elevation = elevation;
      Radius = 3.0;
    };
  };
in
{
  # PipeWire filter-chain configuration for virtual 7.1 surround
  services.pipewire.extraConfig.pipewire."99-virtual-surround" = lib.mkIf (!isVM) {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Virtual Surround 7.1";
          "media.name" = "Virtual Surround 7.1";
          "filter.graph" = {
            nodes = [
              # Front Left speaker - 30° left
              (mkSpatializer "spFL" 30.0 0.0)
              # Front Right speaker - 30° right (330°)
              (mkSpatializer "spFR" 330.0 0.0)
              # Front Center speaker - directly ahead
              (mkSpatializer "spFC" 0.0 0.0)
              # Rear Left speaker - 150° left
              (mkSpatializer "spRL" 150.0 0.0)
              # Rear Right speaker - 210° (150° right)
              (mkSpatializer "spRR" 210.0 0.0)
              # Side Left speaker - 90° left
              (mkSpatializer "spSL" 90.0 0.0)
              # Side Right speaker - 270° (90° right)
              (mkSpatializer "spSR" 270.0 0.0)
              # LFE (subwoofer) - below center
              (mkSpatializer "spLFE" 0.0 (-60.0))
              # Stereo mixers for output
              {
                type = "builtin";
                label = "mixer";
                name = "mixL";
              }
              {
                type = "builtin";
                label = "mixer";
                name = "mixR";
              }
            ];
            links = [
              # Connect all spatializer outputs to the stereo mixers
              {
                output = "spFL:Out L";
                input = "mixL:In 1";
              }
              {
                output = "spFL:Out R";
                input = "mixR:In 1";
              }
              {
                output = "spFR:Out L";
                input = "mixL:In 2";
              }
              {
                output = "spFR:Out R";
                input = "mixR:In 2";
              }
              {
                output = "spFC:Out L";
                input = "mixL:In 3";
              }
              {
                output = "spFC:Out R";
                input = "mixR:In 3";
              }
              {
                output = "spRL:Out L";
                input = "mixL:In 4";
              }
              {
                output = "spRL:Out R";
                input = "mixR:In 4";
              }
              {
                output = "spRR:Out L";
                input = "mixL:In 5";
              }
              {
                output = "spRR:Out R";
                input = "mixR:In 5";
              }
              {
                output = "spSL:Out L";
                input = "mixL:In 6";
              }
              {
                output = "spSL:Out R";
                input = "mixR:In 6";
              }
              {
                output = "spSR:Out L";
                input = "mixL:In 7";
              }
              {
                output = "spSR:Out R";
                input = "mixR:In 7";
              }
              {
                output = "spLFE:Out L";
                input = "mixL:In 8";
              }
              {
                output = "spLFE:Out R";
                input = "mixR:In 8";
              }
            ];
            inputs = [
              "spFL:In"
              "spFR:In"
              "spFC:In"
              "spLFE:In"
              "spRL:In"
              "spRR:In"
              "spSL:In"
              "spSR:In"
            ];
            outputs = [
              "mixL:Out"
              "mixR:Out"
            ];
          };
          "capture.props" = {
            "node.name" = "effect_input.virtual-surround-7.1";
            "media.class" = "Audio/Sink";
            "audio.channels" = 8;
            "audio.position" = [
              "FL"
              "FR"
              "FC"
              "LFE"
              "RL"
              "RR"
              "SL"
              "SR"
            ];
          };
          "playback.props" = {
            "node.name" = "effect_output.virtual-surround-7.1";
            "node.passive" = true;
            "audio.channels" = 2;
            "audio.position" = [
              "FL"
              "FR"
            ];
          };
        };
      }
    ];
  };
}
