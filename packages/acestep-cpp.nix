# acestep.cpp's ace-server, the ACE-Step 1.5 music model over HTTP, on ggml's
# Vulkan backend. Built the way nixpkgs builds llama-cpp with vulkanSupport.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  shaderc,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
}:
stdenv.mkDerivation {
  pname = "acestep-cpp";
  version = "0-unstable-2026-11-17";

  src = fetchFromGitHub {
    owner = "ServeurpersoCom";
    repo = "acestep.cpp";
    rev = "973517be024ff8b6bbd50e0adc9e308ab2ed71b3";
    # ggml is a submodule.
    fetchSubmodules = true;
    hash = "sha256-Gw2Wc2UQ4q5yqXjNLYxw2gjTKrAQ9gISL1si4cVRcF8=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    # glslc compiles ggml's Vulkan shaders at build time.
    shaderc
  ];

  buildInputs = [
    spirv-headers
    vulkan-headers
    vulkan-loader
  ];

  cmakeFlags = [
    (lib.cmakeBool "GGML_VULKAN" true)
    (lib.cmakeBool "GGML_NATIVE" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" false)
  ];

  ninjaFlags = [ "ace-server" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ace-server $out/bin/ace-server
    runHook postInstall
  '';

  meta = {
    description = "ACE-Step 1.5 music generation server in C++ with ggml (Vulkan build)";
    homepage = "https://github.com/ServeurpersoCom/acestep.cpp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ace-server";
  };
}
