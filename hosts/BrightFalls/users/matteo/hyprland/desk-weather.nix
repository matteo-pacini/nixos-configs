# The weather panel's helper, `desk-weather` (protocol: desk-weather.py).
# `configFile` holds the location, the warnings region and the broker; it is
# the default for --config. `testing` adds the flags that point every request
# at a local server and scale the timers; only the weather-helper check
# builds it.
{
  writers,
  python3Packages,
  configFile ? "/run/agenix/brightfalls/weather",
  testing ? false,
}:
writers.writePython3Bin "desk-weather"
  {
    libraries = [ python3Packages.paho-mqtt ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  }
  (
    builtins.replaceStrings
      [ "@config@" "@testing@" ]
      [
        configFile
        (if testing then "yes" else "no")
      ]
      (builtins.readFile ./desk-weather.py)
  )
