{ fetchFromGitHub }:
{
  version = "0-unstable-2026-11-16";
  src = fetchFromGitHub {
    owner = "brcly";
    repo = "legion-kvm";
    rev = "79a6ec06d8c32a3ccd55956671b1e09fc594b8e9";
    hash = "sha256-PEZIpp+vTQhSluKnyuStfWm8ziaYup6HXqCfUQpcsm8=";
  };
}
