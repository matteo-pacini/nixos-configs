{ ... }:

{
  programs.emacs = {
    extraPackages = epkgs: with epkgs; [ nasm-mode ];
    extraConfig = ''
      (use-package nasm-mode
       :mode (("\\.nasm\\'" . nasm-mode)
              ("\\.s\\'" . nasm-mode)
              ("\\.asm\\'" . nasm-mode)))
    '';
  };
}
