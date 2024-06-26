{ ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ which-key ];
    extraConfig = ''
      (use-package which-key
        :config
        (which-key-mode))
    '';
  };
}
