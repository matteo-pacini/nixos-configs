# Calendar events for the Quickshell panel. pimsync mirrors the CalDAV
# account one way and read-only into a vdir; calendar-export then writes the
# file the panel reads. See "Calendar events" in README.md.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  secret = name: osConfig.age.secrets."brightfalls/caldav-${name}".path;
  catSecret = name: "cmd ${lib.getExe' pkgs.coreutils "cat"} ${secret name}";

  vdir = "${config.xdg.dataHome}/calendars";
  workDir = "${config.xdg.cacheHome}/calendar-sync";
  exportFile = "${config.xdg.cacheHome}/desk/calendar/events.jsonl";

  calendarExport = import ./calendar-export.nix { inherit pkgs; };
  khalConfig = calendarExport.khalConfig {
    inherit workDir;
    inherit (osConfig.time) timeZone;
  };
in
{
  # Nothing is ever written to the server: `read_only` makes pimsync refuse
  # any write to it, and `one_way` plans none (local edits are reverted
  # instead). `on_empty sync` lets a calendar emptied on the server empty
  # the local copy too, which under one_way can only touch the local side.
  xdg.configFile."pimsync/pimsync.conf".text = ''
    status_path "${config.xdg.stateHome}/pimsync/"

    pair calendars {
    	storage_a remote
    	storage_b local
    	collections from a
    	one_way
    	on_empty sync
    }

    storage remote {
    	type caldav
    	url {
    		${catSecret "url"}
    	}
    	discovery principal
    	username {
    		${catSecret "user"}
    	}
    	password {
    		${catSecret "password"}
    	}
    	read_only
    	interval 0
    }

    storage local {
    	type vdir/icalendar
    	path ${vdir}/
    	interval 0
    }
  '';

  # Lets the panel open the web calendar without the address being in the
  # repository or in QML: it reads the decrypted file at run time.
  xdg.dataFile."desk/calendar/source.json".text = builtins.toJSON {
    url_file = secret "url";
  };

  systemd.user.services.calendar-sync = {
    Unit.Description = "Calendar sync (read-only) and export for the panel";
    Service = {
      Type = "oneshot";
      # A oneshot has no start timeout by default, so a hung sync would keep
      # the unit active and the timer could never start it again. systemd
      # restarts this limit for each of ExecStartPre, ExecStart and
      # ExecStartPost, so it bounds the export too.
      # Far above a first sync of the whole account on a slow link.
      TimeoutStartSec = "15min";
      # pimsync expects the vdir directory to exist (pimsync(1), `check`).
      ExecStartPre = "${lib.getExe' pkgs.coreutils "mkdir"} -p ${vdir}";
      ExecStart = "${lib.getExe pkgs.pimsync} sync";
      # Runs only when the sync succeeded, so an offline run keeps the last
      # good export (whose header says when it was made).
      ExecStartPost = "${lib.getExe calendarExport.package} ${vdir} ${workDir} ${khalConfig} ${exportFile}";
    };
  };

  systemd.user.timers.calendar-sync = {
    Unit = {
      Description = "Calendar sync every 10 minutes";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Timer = {
      OnActiveSec = "1min";
      # Wall-clock, not OnUnitActiveSec: Persistent= only applies to
      # OnCalendar=, and a monotonic timer would not catch up after suspend.
      OnCalendar = "*:0/10";
      Persistent = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
