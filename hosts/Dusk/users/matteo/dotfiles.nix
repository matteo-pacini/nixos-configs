{ lib, ... }:
{
  home.file."Brewfile".text = ''

    tap "homebrew/bundle"
    tap "homebrew/cask"
    tap "homebrew/core"

    cask_args appdir: '/Applications', require_sha: true

    cask '1password'
  '';

  home.activation.brewUpdate =
    lib.hm.dag.entryAfter
      [
        "linkGeneration"
        "writeBoundary"
      ]
      ''
        export PATH="$PATH:/opt/homebrew/bin"
        $DRY_RUN_CMD brew bundle --file="$HOME/Brewfile" \
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
