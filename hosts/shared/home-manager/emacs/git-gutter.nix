{ ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ git-gutter ];
    extraConfig = ''
      ;; Git gutter
      (use-package git-gutter
        :defer t
        :hook (prog-mode . git-gutter-mode))
    '';
  };
}
