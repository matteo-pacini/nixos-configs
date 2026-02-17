{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.git;
in
{
  options.custom.git = {
    enable = lib.mkEnableOption "Git configuration";
    userName = lib.mkOption {
      type = lib.types.str;
      default = "Matteo Pacini";
      description = "Git user name";
    };
    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "m+github@matteopacini.me";
      description = "Git user email";
    };
    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = "Git editor";
    };
    defaultBranch = lib.mkOption {
      type = lib.types.str;
      default = "master";
      description = "Default branch name for git init";
    };
    sshKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/github";
      description = "Path to SSH key for git operations";
    };
    signing = {
      enable = lib.mkEnableOption "Git commit signing";
      key = lib.mkOption {
        type = lib.types.str;
        default = "~/.ssh/github.pub";
        description = "Path to signing key";
      };
      allowedSignersFile = lib.mkOption {
        type = lib.types.str;
        default = "~/.ssh/allowed_signers";
        description = "Path to allowed signers file";
      };
      allowedSignersContent = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Content of the allowed signers file. If non-empty, the file will be created.";
      };
    };
    diffMergeTool = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Diff/merge tool to use (e.g. nvimdiff)";
    };
    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra git aliases";
    };
    includes = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Git conditional includes";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.git = {
        enable = true;
        lfs.enable = true;
        settings = {
          user = {
            name = cfg.userName;
            email = cfg.userEmail;
          };
          init.defaultBranch = cfg.defaultBranch;
          core.editor = cfg.editor;
          core.sshCommand = "ssh -i ${cfg.sshKeyPath}";
          push.autoSetupRemote = true;
        };
      };
    }
    (lib.mkIf (cfg.extraAliases != { }) {
      programs.git.settings.alias = cfg.extraAliases;
    })
    (lib.mkIf (cfg.diffMergeTool != null) {
      programs.git.settings = {
        diff.tool = cfg.diffMergeTool;
        merge.tool = cfg.diffMergeTool;
      };
    })
    (lib.mkIf cfg.signing.enable {
      programs.git.settings = {
        commit.gpgsign = true;
        gpg.format = "ssh";
        gpg.ssh.allowedSignersFile = cfg.signing.allowedSignersFile;
        user.signingkey = cfg.signing.key;
      };
    })
    (lib.mkIf (cfg.signing.enable && cfg.signing.allowedSignersContent != "") {
      home.file."${cfg.signing.allowedSignersFile}".text = cfg.signing.allowedSignersContent;
    })
    (lib.mkIf (cfg.includes != [ ]) {
      programs.git.includes = cfg.includes;
    })
  ]);
}
