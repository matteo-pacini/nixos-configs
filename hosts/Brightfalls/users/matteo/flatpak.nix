{
  config,
  pkgs,
  inputs,
  ...
}:
{
  home.file."scripts/setup_flatpak.sh".text = ''
    #!/usr/bin/env bash

    flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    # Flatseal
    flatpak --user install -y --noninteractive com.github.tchx84.Flatseal

    # Discord
    flatpak --user install -y --noninteractive com.discordapp.Discord

    # Telegram
    flatpak --user install -y --noninteractive org.telegram.desktop
  '';

  home.file."scripts/setup_flatpak.sh".executable = true;
}
