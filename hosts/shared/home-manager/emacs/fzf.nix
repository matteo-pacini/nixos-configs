{ pkgs, lib, ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ fzf ];
    extraConfig = ''
      ;; fzf
      (use-package fzf
        :config
        (setq fzf/args "-x --color bw --print-query --margin=1,0 --no-hscroll"
              fzf/executable "${lib.getExe pkgs.fzf}"
              fzf/git-grep-args "-i --line-number %s"
              fzf/grep-command "${lib.getExe pkgs.ripgrep} --no-heading -nH"
              fzf/position-bottom t
              fzf/window-height 15)
        :general
        (:keymaps 'global
            :prefix "C-c"
            "f"   'fzf-find-file
            "C-f" 'fzf-find-file-in-dir))
    '';
  };
}
