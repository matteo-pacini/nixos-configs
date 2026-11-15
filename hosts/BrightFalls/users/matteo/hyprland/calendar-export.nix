# The calendar export step, shared by calendar.nix and its flake check so
# both run the same script against the same khal settings.
{ pkgs }:
{
  package =
    pkgs.writers.writePython3Bin "calendar-export"
      {
        # icalendar and pytz from the same package set as khal, so the
        # script resolves time zones exactly as khal does.
        libraries = with pkgs.python3Packages; [
          icalendar
          pytz
        ];
        flakeIgnore = [
          "E501"
          "W503"
        ];
      }
      (
        builtins.replaceStrings [ "@khal@" ] [ (pkgs.lib.getExe' pkgs.khal "khal") ] (
          builtins.readFile ./calendar-export.py
        )
      );

  # khal reads the derived copy calendar-export keeps under workDir/vdir.
  # ISO formats: the export's start/end strings are these formats verbatim.
  khalConfig =
    { workDir, timeZone }:
    pkgs.writeText "calendar-export-khal.conf" ''
      [calendars]
      [[calendars]]
      path = ${workDir}/vdir/*
      type = discover

      [locale]
      local_timezone = ${timeZone}
      default_timezone = ${timeZone}
      timeformat = %H:%M
      dateformat = %Y-%m-%d
      longdateformat = %Y-%m-%d
      datetimeformat = %Y-%m-%d %H:%M
      longdatetimeformat = %Y-%m-%d %H:%M

      [sqlite]
      path = ${workDir}/khal.db
    '';
}
