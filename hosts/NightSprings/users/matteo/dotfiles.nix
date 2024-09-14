{ lib, ... }:
{
  home.file."Brewfile".text = ''

    tap "homebrew/bundle"
    tap "homebrew/cask"
    tap "homebrew/core"

    cask_args appdir: '/Applications', require_sha: true

    cask '1password'
    cask 'mullvadvpn'
    cask 'dash'
    cask 'telegram'
    cask 'whatsapp'
    cask 'zerotier-one'
    cask 'jellyfin-media-player'
    cask 'sf-symbols'
    cask 'logitune', args: { require_sha: false }
    cask 'vlc'
    cask 'element'
    cask 'utm'
  '';

  home.activation.brewUpdate =
    lib.hm.dag.entryAfter
      [
        "linkGeneration"
        "writeBoundary"
      ]
      ''
        $DRY_RUN_CMD /run/current-system/sw/bin/brew bundle \
          --file="$HOME/Brewfile" \
          --no-lock \
          --cleanup --zap \
          --verbose \
          install
      '';

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    vscode.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
  };
}
