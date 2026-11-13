# The Proton build legion-kvm's Wine repair recipe is pinned to
# (config/compatibility.json). The compat tool holds real files rather than
# store symlinks: legion shares the selected Proton directory into the guest
# over virtiofs, where /nix/store does not exist.
{ proton-ge-bin, fetchzip }:
proton-ge-bin.overrideAttrs (
  finalAttrs: old: {
    version = "GE-Proton11-11";
    __intentionallyOverridingVersion = true;
    steamDisplayName = "GE-Proton11-11 (Legion)";
    passthru = old.passthru // {
      variants = old.passthru.variants // {
        x86_64-linux = {
          toolName = "${finalAttrs.version}-x86_64";
          src = fetchzip {
            url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz";
            hash = "sha256-3tVgf83IkteFtVo/bHd4yG1xCtPeuW8FXaTrHOLjvKQ=";
          };
        };
      };
    };
    installPhase = ''
      runHook preInstall
      echo "${finalAttrs.pname} should not be installed into environments. Please use programs.steam.extraCompatPackages instead." > $out
      cp -r --no-preserve=ownership $src $steamcompattool
      chmod u+w $steamcompattool $steamcompattool/compatibilitytool.vdf
      runHook postInstall
    '';
  }
)
