{ config, pkgs, inputs, ... }:

{
  home.file.".mozilla/firefox/matteo/chrome/firefox-gnome-theme".source = inputs.firefox-gnome-theme;

  programs.firefox.enable = true;
  programs.firefox.profiles.matteo = {
    userChrome = ''
      @import "firefox-gnome-theme/userChrome.css";
    '';
    userContent = ''
      @import "firefox-gnome-theme/userContent.css";
    '';
    settings = {
      ## Firefox gnome theme ## - https://github.com/rafaelmardojai/firefox-gnome-theme/blob/7cba78f5216403c4d2babb278ff9cc58bcb3ea66/configuration/user.js
      # (copied into here because home-manager already writes to user.js)
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # Enable customChrome.cs
      "browser.uidensity" = 0; # Set UI density to normal
      "svg.context-properties.content.enabled" = true; # Enable SVG context-propertes
      "browser.theme.dark-private-windows" = false; # Disable private window dark theme
    };
  };

}
