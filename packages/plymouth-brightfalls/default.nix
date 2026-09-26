# Plymouth theme for BrightFalls: the NixOS snowflake assembling from six
# lambdas, then a seamless loop while the LUKS prompt waits. Frames are
# rendered at build time from render.html with headless Chromium on
# SwiftShader (CPU), so the build needs no GPU; it takes under a minute.
{
  lib,
  stdenvNoCC,
  fetchurl,
  chromium,
  pngquant,
  jost,
  jetbrains-mono,
}:
let
  three = fetchurl {
    url = "https://registry.npmjs.org/three/-/three-0.170.0.tgz";
    hash = "sha256-SmCKNV3KunLg5Tg83IFDA/W2BgtDwjjN9pMtzraZI40=";
  };

  # Separate derivation so edits to the script or descriptor don't re-render.
  frames = stdenvNoCC.mkDerivation {
    pname = "plymouth-brightfalls-frames";
    version = "1";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = ./render.html;
    };

    nativeBuildInputs = [
      chromium
      pngquant
    ];

    buildPhase = ''
      runHook preBuild

      mkdir -p work/three work/fonts frames
      tar xzf ${three} --strip-components=1 -C work/three package/build package/examples
      cp render.html work/
      cp ${jost}/share/fonts/truetype/Jost-300-Light.ttf work/fonts/
      cp ${jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf work/fonts/

      export HOME=$TMPDIR
      # --dump-dom prints the DOM once virtual time is spent, but Chromium does
      # not always exit afterwards; stop it once the DONE sentinel is out.
      chromium --headless=new --no-sandbox \
        --use-angle=swiftshader --enable-unsafe-swiftshader \
        --allow-file-access-from-files \
        --virtual-time-budget=3600000 \
        --dump-dom "file://$PWD/work/render.html" > dom.html 2> chromium.log &
      pid=$!
      deadline=$((SECONDS + 3600))
      until grep -q '^DONE$' dom.html; do
        if ! kill -0 $pid 2>/dev/null || ((SECONDS > deadline)); then
          cat chromium.log >&2
          echo "chromium did not finish rendering" >&2
          exit 1
        fi
        sleep 5
      done
      kill $pid || true

      grep -oE 'FILE [a-z0-9.-]+ [A-Za-z0-9+/=]+' dom.html | while read -r _ name data; do
        printf '%s' "$data" | base64 -d > "frames/$name"
      done

      # Palette-quantised frames are ~10x smaller; they all live in the initrd.
      pngquant --quality=40-90 --speed 1 --force --ext .png frames/*.png

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp frames/*.png $out/
      runHook postInstall
    '';
  };
in
stdenvNoCC.mkDerivation {
  pname = "plymouth-brightfalls";
  version = "1";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./brightfalls.script
      ./brightfalls.plymouth
    ];
  };

  installPhase = ''
    runHook preInstall

    themeDir=$out/share/plymouth/themes/brightfalls
    mkdir -p $themeDir
    cp ${frames}/*.png brightfalls.script $themeDir/
    substitute brightfalls.plymouth $themeDir/brightfalls.plymouth \
      --subst-var themeDir

    runHook postInstall
  '';

  passthru = { inherit frames; };

  meta = {
    description = "Cinematic NixOS snowflake Plymouth theme for BrightFalls";
    platforms = lib.platforms.linux;
  };
}
