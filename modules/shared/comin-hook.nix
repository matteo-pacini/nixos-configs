# comin postDeploymentCommand: reports deployments to Telegram.
#
# Failures are always reported. When notifyStaged is set, a successful
# deployment whose system differs from the booted one is reported as
# "reboot pending" (meant for operation = "boot"); deployments that produce
# the already-booted system stay silent.
{
  pkgs,
  telegramEnvFile,
  telegramPrefix ? "",
  notifyStaged ? false,
}:
pkgs.writeShellScript "comin-post-deploy" ''
  set -euo pipefail

  # comin's launchd daemon on Darwin runs with a PATH of nix, git and ssh only.
  export PATH=${
    pkgs.lib.makeBinPath [
      pkgs.coreutils
      pkgs.gnused
    ]
  }:$PATH
  export TELEGRAM_ENV_FILE=${pkgs.lib.escapeShellArg telegramEnvFile}
  export TELEGRAM_PREFIX=${pkgs.lib.escapeShellArg telegramPrefix}

  # Legacy Markdown entities; an unescaped one makes Telegram reject the message.
  md_escape() { sed 's/[_*`[]/\\&/g'; }

  sha=$(printf '%s' "''${COMIN_GIT_SHA:0:7}" | md_escape)
  subject=$(printf '%s\n' "$COMIN_GIT_MSG" | head -n1 | md_escape)

  case "$COMIN_STATUS" in
    failed)
      error=$(printf '%s' "$COMIN_ERROR_MSG" | head -c 1000 | md_escape)
      ${pkgs.telegram-notify}/bin/telegram-notify \
        "🚨 @matteopacini deploy of \`$sha\` failed ($subject): $error"
      ;;
    done)
      ${pkgs.lib.optionalString notifyStaged ''
        booted=$(readlink -f /run/booted-system)
        staged=$(readlink -f /nix/var/nix/profiles/system-profiles/comin)
        if [[ "$booted" != "$staged" ]]; then
          ${pkgs.telegram-notify}/bin/telegram-notify \
            "📦 @matteopacini \`$sha\` staged ($subject), reboot pending"
        fi
      ''}
      ;;
  esac
''
