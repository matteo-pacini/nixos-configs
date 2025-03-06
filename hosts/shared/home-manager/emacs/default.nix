{ pkgs, lib, ... }:
{
  imports = [
    ./org.nix
    ./copilot.nix
    ./nix.nix
    ./lsp.nix
    ./doom.nix
    ./which-key.nix
    ./neotree.nix
    ./git-gutter.nix
    ./fzf.nix
    ./general.nix
    ./reformatter.nix
    ./swift.nix
    ./nasm.nix
  ];

  programs.emacs =
    let
      emacs = pkgs.emacs;
    in
    {
      enable = true;
      package = emacs;
      extraPackages = epkgs: with epkgs; [ use-package ];
      extraConfig = ''

        ;; use-package
        (eval-when-compile
          (require 'use-package))
        (setq use-package-always-ensure nil)

        ;; UI Fixes
        (setq inhibit-startup-screen t)
        (setq initial-scratch-message nil)
        (tool-bar-mode -1)
        (menu-bar-mode -1)
        (scroll-bar-mode -1)
        (setq visible-bell t)

        ;; Avoid clutter
        (setq make-backup-files nil)
        (setq auto-save-default nil)
        (setq create-lockfiles nil)
        (setq warning-minimum-level :error)

        ;; "y" or "n" is enough
        (defalias 'yes-or-no-p 'y-or-n-p)

        ;; Line numbers
        (global-display-line-numbers-mode)

        (setq tab-width 4)          ; and 4 char wide for TAB
        (setq indent-tabs-mode nil) ; And force use of spaces

        ;; Revert buffers automatically when underlying files change
        (global-auto-revert-mode t)

        ;; UTF-8
        (prefer-coding-system 'utf-8)
        (set-language-environment 'utf-8)
        (set-default-coding-systems 'utf-8)
        (set-terminal-coding-system 'utf-8)

        ;; Open Emacs ref card link
        (defun open-emacs-ref-card ()
          (interactive)
          (browse-url "https://www.gnu.org/software/emacs/refcards/pdf/refcard.pdf"))
        (global-set-key (kbd "C-h C-r") 'open-emacs-ref-card)

        ;; Font
        (set-face-attribute 'default nil :font "FiraCode Nerd Font" :height 180)
      '';
    };

  programs.zsh.shellAliases = lib.mkIf pkgs.stdenv.isDarwin {
    emacs = "$HOME/Applications/'Home Manager Apps'/Emacs.app/Contents/MacOS/Emacs";
  };
}
