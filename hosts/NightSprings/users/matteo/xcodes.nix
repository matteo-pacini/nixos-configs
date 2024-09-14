{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
      "16.0 Release Candidate"
      "16.1 Beta"
    ];
    active = "15.4";
  };
}
