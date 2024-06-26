{ ... }:

{
  programs.emacs = {
    extraPackages =
      epkgs: with epkgs; [
        nerd-icons
        doom-modeline
        doom-themes
      ];
    extraConfig = ''
      ;; nerd-icons
      (use-package nerd-icons)

      ;; doom-modeline
      (use-package doom-modeline
        :init (doom-modeline-mode 1))

      (use-package doom-themes
        :config
        (setq doom-themes-enable-bold t   
              doom-themes-enable-italic t)
        (load-theme 'doom-dracula t)
        ;; Enable flashing mode-line on errors
        (doom-themes-visual-bell-config)
        ;; Enable custom neotree theme (all-the-icons must be installed!)
        (doom-themes-neotree-config)
        ;; Corrects (and improves) org-mode's native fontification.
        (doom-themes-org-config))
    '';
  };
}
