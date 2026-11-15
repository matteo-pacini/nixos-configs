{ fetchFromGitHub }:
{
  version = "0-unstable-2026-11-15";
  src = fetchFromGitHub {
    owner = "brcly";
    repo = "legion-kvm";
    rev = "2e2738835d48327411bce2e7a14aba8b2d48e517";
    hash = "sha256-zEDuJYfOLCMeVt5do1xh025LC6OBhvR41ShLb5EkWA4=";
  };
}
