{ ... }:
{
  imports = [
    ./openssh.nix
    ./smartd.nix
    ./jellyfin.nix
    ./backup.nix
  ];

  # To control /diskpool/media access
  users.groups.media = { };
}
