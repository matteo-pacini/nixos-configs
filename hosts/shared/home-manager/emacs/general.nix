{ ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ general ];
    extraConfig = ''
      ;; General
      (use-package general)
    '';
  };
}
