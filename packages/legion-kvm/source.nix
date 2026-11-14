{ fetchFromGitHub }:
{
  version = "0-unstable-2026-11-13";
  src = fetchFromGitHub {
    owner = "brcly";
    repo = "legion-kvm";
    rev = "0c0dee703e0c378a0448bf8905082c18dd7080d5";
    hash = "sha256-SfYN2c31g2/FBGbcDpt+c+b3PZQTMty6KUdtu/sbqbo=";
  };
}
