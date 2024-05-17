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
    cask 'mullvadvpn'
    cask 'dash'
    cask 'telegram'
    cask 'whatsapp'
    cask 'utm'
    cask 'zerotier-one'
    cask 'jellyfin-media-player'
    cask 'sf-symbols'
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

  wallpapers.dracula = {
    enable = true;
  };
}
