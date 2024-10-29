{ lib, ... }:
{
  home.file."Brewfile".text = ''

    tap "homebrew/bundle"
    tap "homebrew/cask"
    tap "homebrew/core"

    cask_args appdir: '/Applications', require_sha: true

    cask '1password'
    cask 'microsoft-teams'
    cask 'microsoft-outlook'
    cask 'slack'
    cask 'sf-symbols'
    cask 'figma'
    cask 'logitune', args: { require_sha: false }
    cask 'utm'
    cask 'android-studio'
    cask 'jellyfin-media-player'
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
