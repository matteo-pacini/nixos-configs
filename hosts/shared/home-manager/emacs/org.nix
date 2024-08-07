{ pkgs, lib, ... }:

let
  orgTexLiveMinimal = (
    pkgs.texlive.combine {
      inherit (pkgs.texlive)
        scheme-basic
        dvisvgm
        dvipng
        wrapfig
        amsmath
        ulem
        hyperref
        capt-of
        etoolbox
        ;
    }
  );
in
{
  programs.emacs = {
    extraPackages =
      epkgs: with epkgs; [
        org
        org-download
        org-superstar
        ox-reveal
        htmlize
      ];
    extraConfig =
      lib.optionalString pkgs.stdenv.isDarwin ''

        (add-to-list 'exec-path "${pkgs.pngpaste}/bin")

      ''
      + ''

        ;; Add graphviz to PATH
        (setenv "PATH" (concat (getenv "PATH") ":${pkgs.graphviz}/bin"))

        ;; Add texlive to PATH
        (setenv "PATH" (concat (getenv "PATH") ":${orgTexLiveMinimal}/bin"))

        (use-package org
          :mode ("\\.org\\'" . org-mode)
          :config
          (setq-default org-ellipsis " ⤵"
                        org-startup-indented t
                        org-pretty-entities t
                        org-pretty-entities-include-sub-superscripts t
                        org-use-sub-superscripts "{}"
                        org-hide-emphasis-markers t
                        org-startup-with-inline-images t
                        org-image-actual-width '(300)
                        org-display-custom-times t
                        org-time-stamp-custom-formats '("<%d %b %Y>" . "<%d/%m/%y %a %H:%M>")
                        org-confirm-babel-evaluate nil
                        org-latex-compiler "lualatex"
                        org-preview-latex-default-process 'dvisvgm)
          (org-babel-do-load-languages
            'org-babel-load-languages
              '((shell . t)
                (dot . t)))
          :general
          (:keymaps 'global
           :prefix "C-c"
           "a" 'org-agenda))
                    
        (use-package org-superstar
          :after org
          :hook (org-mode . org-superstar-mode))

        (use-package ox-reveal
          :after org
          :config
          (setq org-reveal-root "https://cdn.jsdelivr.net/npm/reveal.js"))

        (use-package htmlize
          :after org)

        (use-package org-download
          :hook (dired-mode . org-download-enable)
          :config
          (setq-default org-download-image-dir "./images/")
          (setq org-download-method 'directory
                org-download-display-inline-images t
                org-download-image-attr-list '("#+ATTR_HTML: :width 400 :align center")))
      '';
  };
}
