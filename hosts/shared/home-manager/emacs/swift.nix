{ pkgs, ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ swift-mode ];
    extraConfig = ''

      (use-package swift-mode
        :mode "\\.swift\\'"
        :interpreter "swift")

    '';
  };
}
