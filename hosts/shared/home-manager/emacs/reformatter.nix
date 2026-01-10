{ pkgs, ... }:
let
  formatters = pkgs.symlinkJoin {
    name = "nix-packages";
    paths = with pkgs; [ nixfmt ];
  };
in
{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ reformatter ];
    extraConfig = ''
      (add-to-list 'exec-path "${formatters}/bin")

      (use-package reformatter
        :config
        (reformatter-define nixfmt-rfc-style
          :program "nixfmt" 
          :lighter "NixFmtRfcStyle" 
          :group 'nixfmt-rfc-style))
    '';
  };
}
