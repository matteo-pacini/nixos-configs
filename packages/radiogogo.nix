{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  ffmpeg_5-full,
  makeWrapper,
}: let
  version = "0.3.1";
in
  buildGoModule {
    pname = "radiogogo";
    inherit version;

    src = fetchFromGitHub {
      owner = "matteo-pacini";
      repo = "RadioGoGo";
      rev = "v${version}";
      hash = "sha256-Yb1K/nC41K8AoXWSB/8aDVCNDe06bvsSON1wwGPrSgI=";
    };

    vendorHash = "sha256-h/ipRovm/fmfA2Wanx0Hp8Om2yTEZ1zZRCJ19LGP/NE=";

    nativeBuildInputs = [makeWrapper];

    postInstall = ''
      wrapProgram $out/bin/radiogogo \
          --prefix PATH : ${lib.makeBinPath [ffmpeg_5-full]}
    '';

    meta = with lib; {
      homepage = "https://github.com/matteo=pacini/RadioGoGo";
      description = "Go-powered CLI to surf global radio waves via a sleek TUI";
      license = licenses.mit;
      maintainers = with maintainers; [matteopacini];
    };
  }
