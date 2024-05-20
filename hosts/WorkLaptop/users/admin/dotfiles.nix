{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  home.file.".config/colorls/dark_colors.yaml".source = "${inputs.colorls-dracula-theme}/dark_colors.yaml";

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
  '';

  home.activation.brewUpdate =
    lib.hm.dag.entryAfter [
      "linkGeneration"
      "writeBoundary"
    ] ''
      export PATH="$PATH:/opt/homebrew/bin"
      $DRY_RUN_CMD brew bundle --file="$HOME/Brewfile" \
        --no-lock \
        --cleanup --zap \
        --verbose \
        install
    '';

  home.file.".config/asciinema/config".text = ''
    [record]
    command = ${config.programs.zsh.package}/bin/zsh
  '';

  wallpapers.dracula = {
    enable = true;
  };
}
