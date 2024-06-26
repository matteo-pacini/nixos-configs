{ pkgs, ... }:
let
  languageServers = pkgs.symlinkJoin {
    name = "nix-packages";
    paths = with pkgs; [ nil ];
  };
in
{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ lsp-mode ];
    extraConfig = ''
      (add-to-list 'exec-path "${languageServers}/bin")

      ;; LSP
      (use-package lsp-mode
        :commands (lsp lsp-deferred))
    '';
  };
}
