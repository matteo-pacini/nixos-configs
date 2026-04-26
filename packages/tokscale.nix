{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  sqlite,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tokscale";
  version = "2.0.27";

  src = fetchFromGitHub {
    owner = "junhoyeo";
    repo = "tokscale";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mVd7kNjZ9fo/ITwMaLtq7f5uLB/gpwP7Fd+RhAjAq8U=";
  };

  cargoHash = "sha256-0n/CgX0ccDoHHXRaTDqJb1iEVJ8ZhC5yKe74n6KdIEM=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    openssl
    sqlite
  ];

  env = {
    OPENSSL_NO_VENDOR = true;
  };

  checkFlags = [
    # Tries to make network requests to other hosts
    "--skip=test_graph_single_day_filter_uses_local_timezone_boundaries"
    "--skip=test_pricing_command_json"
    "--skip=test_pricing_command_success"
    "--skip=test_pricing_command_with_provider"
  ];

  meta = {
    description = "CLI tool for tracking token usage from various agentic coding tools like Claude Code and OpenCode etc.";
    downloadPage = "https://github.com/junhoyeo/tokscale";
    homepage = "https://tokscale.ai";
    changelog = "https://github.com/junhoyeo/tokscale/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "tokscale";
  };
})
