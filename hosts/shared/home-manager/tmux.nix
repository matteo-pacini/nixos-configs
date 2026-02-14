{
  pkgs,
  lib,
  ...
}:
{
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    shell = "${pkgs.zsh}/bin/zsh";
    clock24 = true;
    terminal = "tmux-256color";
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = dracula;
        extraConfig =
          ''
            set -g @dracula-show-powerline true
            set -g @dracula-refresh-rate 10
          ''
          + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
            set -g @dracula-show-battery true
            set -g @dracula-show-fahrenheit false
            set -g @dracula-fixed-location "Royal Tunbridge Wells"
          ''
          + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            set -g @dracula-plugins "time"
          '';
      }
    ];

    extraConfig = ''
      set -g mouse on
      set-option -g default-command ''${SHELL}
      set-option -g default-shell ''${SHELL}

      # smart-splits.nvim integration
      # Navigation: C-h/j/k/l moves between neovim splits and tmux panes seamlessly
      bind-key -n C-h if -F "#{@pane-is-vim}" 'send-keys C-h' 'select-pane -L'
      bind-key -n C-j if -F "#{@pane-is-vim}" 'send-keys C-j' 'select-pane -D'
      bind-key -n C-k if -F "#{@pane-is-vim}" 'send-keys C-k' 'select-pane -U'
      bind-key -n C-l if -F "#{@pane-is-vim}" 'send-keys C-l' 'select-pane -R'

      # Resizing: M-h/j/k/l resizes neovim splits or tmux panes
      bind-key -n M-h if -F "#{@pane-is-vim}" 'send-keys M-h' 'resize-pane -L 3'
      bind-key -n M-j if -F "#{@pane-is-vim}" 'send-keys M-j' 'resize-pane -D 3'
      bind-key -n M-k if -F "#{@pane-is-vim}" 'send-keys M-k' 'resize-pane -U 3'
      bind-key -n M-l if -F "#{@pane-is-vim}" 'send-keys M-l' 'resize-pane -R 3'

      # Copy mode navigation
      bind-key -T copy-mode-vi 'C-h' select-pane -L
      bind-key -T copy-mode-vi 'C-j' select-pane -D
      bind-key -T copy-mode-vi 'C-k' select-pane -U
      bind-key -T copy-mode-vi 'C-l' select-pane -R
    '';
  };
}
