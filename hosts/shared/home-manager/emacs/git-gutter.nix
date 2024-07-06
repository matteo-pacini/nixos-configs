{ ... }:

{
  programs.emacs = {
    extraPackages =
      epkgs: with epkgs; [
        git-gutter
        git-gutter-fringe
      ];
    extraConfig = ''

      ;; https://web.archive.org/web/20240706085719/https://ianyepan.github.io/posts/emacs-git-gutter/

      ;; Git gutter
      (use-package git-gutter
        :defer t
        :hook (prog-mode . git-gutter-mode)
        :config
        (setq git-gutter:update-interval 0.02))

      (use-package git-gutter-fringe
        :after git-gutter
        :config
        (define-fringe-bitmap 'git-gutter-fr:added [224] nil nil '(center repeated))
        (define-fringe-bitmap 'git-gutter-fr:modified [224] nil nil '(center repeated))
        (define-fringe-bitmap 'git-gutter-fr:deleted [128 192 224 240] nil nil 'bottom))
    '';
  };
}
