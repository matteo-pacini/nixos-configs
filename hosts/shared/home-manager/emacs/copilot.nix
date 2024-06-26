{ pkgs, lib, ... }:

{
  programs.emacs = {
    extraPackages =
      epkgs: with epkgs; [
        (copilot.overrideAttrs (oldAttrs: {
          meta.platforms = oldAttrs.meta.platforms ++ [ "aarch64-darwin" ];
        }))
      ];
    extraConfig = ''
      ;; Copilot
      (use-package copilot
        :defer t
        :general
        (:keymaps 'copilot-mode-map
             :prefix "C-c C-c"
             "l" 'copilot-next-completion
             "h" 'copilot-previous-completion
             "j" 'copilot-accept-completion
             "d" 'copilot-diagnose)
        :hook
          (prog-mode . copilot-mode)
        :custom
          (copilot-node-executable "${lib.getExe pkgs.nodejs}")
      )

      (general-define-key :prefix "C-c C-c"
        "e" 'copilot-mode)
       
    '';
  };
}
