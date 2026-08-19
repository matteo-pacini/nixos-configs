{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.sleepmode;

  # disablesleep is a system-wide pmset setting, hence sudo. The value is
  # inverted with respect to the argument: "on" means the Mac may sleep.
  sleepmode = pkgs.writeShellApplication {
    name = "sleepmode";
    runtimeInputs = [ pkgs.gawk ];
    text = ''
      usage() {
        echo "usage: sleepmode on|off" >&2
        exit 2
      }

      [ $# -eq 1 ] || usage

      case "$1" in
        on) want=0 ;;
        off) want=1 ;;
        *) usage ;;
      esac

      /usr/bin/sudo /usr/bin/pmset -a disablesleep "$want"

      # Absent SleepDisabled line means sleep is allowed.
      actual=$(/usr/bin/pmset -g \
        | awk '/SleepDisabled/ { print $2; found = 1 } END { if (!found) print 0 }')

      if [ "$actual" != "$want" ]; then
        printf '\033[1;31mFAILED\033[0m sleep mode unchanged (disablesleep = %s)\n' "$actual" >&2
        exit 1
      fi

      if [ "$actual" = 0 ]; then
        printf '\033[1;32mSleep mode ACTIVATED\033[0m - this Mac can sleep\n'
      else
        printf '\033[1;33mSleep mode DEACTIVATED\033[0m - this Mac will stay awake\n'
      fi
    '';
  };

  sleepmode-completion = pkgs.writeTextFile {
    name = "sleepmode-zsh-completion";
    destination = "/share/zsh/site-functions/_sleepmode";
    text = ''
      #compdef sleepmode

      _sleepmode() {
        _arguments -C \
          '1:mode:((on\:"allow this Mac to sleep" off\:"keep this Mac awake"))'
      }

      _sleepmode "$@"
    '';
  };
in
{
  options.custom.sleepmode = {
    enable = lib.mkEnableOption "sleepmode helper for pmset disablesleep";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      sleepmode
      sleepmode-completion
    ];
  };
}
