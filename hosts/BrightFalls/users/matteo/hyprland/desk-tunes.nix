# The tunes panel's service and client, `desk-tunes` (protocol:
# desk-tunes.py). `configFile` is the default for --config; every program it
# runs except hyprctl is baked in here, so `serve --<program>` flags are only
# for tests. `testing` adds the --test-* flags and the test_timers command;
# only the tunes-helper check builds it.
{
  lib,
  writers,
  acestep-cpp,
  mpv,
  mpvScripts,
  ffmpeg,
  vulkan-tools,
  configFile,
  testing ? false,
}:
writers.writePython3Bin "desk-tunes"
  {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  }
  (
    builtins.replaceStrings
      [
        "@config@"
        "@ace_server@"
        "@mpv@"
        "@mpris@"
        "@ffmpeg@"
        "@ffprobe@"
        "@vulkaninfo@"
        "@testing@"
      ]
      [
        "${configFile}"
        (lib.getExe' acestep-cpp "ace-server")
        (lib.getExe mpv)
        "${mpvScripts.mpris}/share/mpv/scripts/mpris.so"
        (lib.getExe' ffmpeg "ffmpeg")
        (lib.getExe' ffmpeg "ffprobe")
        (lib.getExe' vulkan-tools "vulkaninfo")
        (if testing then "yes" else "no")
      ]
      (builtins.readFile ./desk-tunes.py)
  )
