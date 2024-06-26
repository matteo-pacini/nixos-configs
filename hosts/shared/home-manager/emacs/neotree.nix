{ ... }:

{
  programs.emacs = {
    extraPackages =
      epkgs: with epkgs; [
        neotree
        all-the-icons
      ];
    extraConfig = ''
      (use-package neotree
        :general
        ("<f8>" 'neotree-toggle)
        :config
        ;; Disable line-numbers in neotree
        (add-hook 'neo-after-create-hook
                  (lambda (&rest _) (display-line-numbers-mode -1)))
        (setq neo-smart-open t)
        (setq neo-vc-integration '(face)))
    '';
  };
}
