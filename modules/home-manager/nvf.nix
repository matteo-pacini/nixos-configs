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
  options.custom.nvf = {
    enable = lib.mkEnableOption "Neovim configuration via nvf";

    completion = {
      enable = lib.mkEnableOption "inline FIM code completion via llama.vim";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8012";
        description = ''
          Base URL of the llama.cpp server, without a path — llama.vim appends
          /infill itself. Matches custom.code-completion-model's defaults.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nvf = {
      enable = true;
      defaultEditor = true;
      settings = lib.mkMerge [
        { imports = [ ../nvf ]; }
        (lib.mkIf cfg.completion.enable {
          vim = {
            startPlugins = [ pkgs.vimPlugins.llama-vim ];

            # Set as a global rather than in luaConfigRC because llama.vim
            # merges g:llama_config over its defaults while sourcing, which
            # happens after init.lua. Partial tables are fine.
            globals.llama_config = {
              endpoint_fim = "${cfg.completion.endpoint}/infill";
              endpoint_inst = "${cfg.completion.endpoint}/v1/chat/completions";
              # llama.vim wants <Tab>/<S-Tab> to accept, but nvf hands those to
              # nvim-cmp for next/previous item. <C-y> and <C-g> are unclaimed.
              keymap_fim_accept_full = "<C-y>";
              keymap_fim_accept_line = "<C-g>";
            };
          };
        })
      ];
    };
  };
}
