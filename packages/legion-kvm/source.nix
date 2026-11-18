{ fetchFromGitHub }:
{
  version = "0-unstable-2026-11-16";
  src = fetchFromGitHub {
    owner = "brcly";
    repo = "legion-kvm";
    rev = "0197712f1a12ce70411d575b33306349c7b19c37";
    hash = "sha256-ueGj8tjq6Bp9v7dydgbgf66fxzf+zg9P6Xw0MhTMNpo=";
  };
}
