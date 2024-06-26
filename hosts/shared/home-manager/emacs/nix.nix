{ pkgs, ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ nix-mode ];
    extraConfig = ''
      (use-package nix-mode
        :mode "\\.nix\\'"
        :hook (
          (nix-mode . lsp-deferred)
          (nix-mode . nixfmt-rfc-style-on-save-mode)
        )
      )
    '';
  };
}
