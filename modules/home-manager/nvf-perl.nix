{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.nvf;
in
{
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim = {
      lsp.servers.perlnavigator = {
        cmd = [
          (lib.getExe pkgs.perlnavigator)
          "--stdio"
        ];
        filetypes = [ "perl" ];
        root_markers = [
          "cpanfile"
          "Makefile.PL"
          "Build.PL"
          ".git"
        ];
        settings.perlnavigator = {
          enableWarnings = true;
          perlcriticEnabled = true;
        };
      };

      treesitter.grammars = [
        pkgs.vimPlugins.nvim-treesitter.grammarPlugins.perl
      ];

      formatter.conform-nvim.setupOpts.formatters_by_ft.perl = [ "perltidy" ];

      diagnostics.nvim-lint = {
        enable = true;
        linters_by_ft.perl = [ "perlcritic" ];
      };

      extraPackages = [
        pkgs.perlPackages.PerlTidy
        pkgs.perlcritic
      ];
    };
  };
}
