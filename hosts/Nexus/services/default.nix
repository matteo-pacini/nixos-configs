{ ... }:
{
  imports = [
    ./openssh.nix
    ./smartd.nix
    ./jellyfin.nix
  ];

  # To control /diskpool/media access
  users.groups.media = { };
}
