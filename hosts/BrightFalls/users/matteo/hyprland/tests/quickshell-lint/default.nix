# The shell's QML through qmllint, laid out as Quickshell's scanner sees it,
# against Quickshell's and Qt's installed QML; its `qs ipc call`s (binds and
# QML) against its IpcHandlers; then each of those on a copy with one fault
# planted, which must fail. desk-nest's root, nest/dev.qml, is linted at the
# root of a copy of the tree. See run.sh; accepted warnings are in allowlist.
{ pkgs }:
pkgs.runCommand "quickshell-lint"
  {
    nativeBuildInputs = [
      pkgs.kdePackages.qtdeclarative
      pkgs.jq
      pkgs.nodejs
    ];
  }
  ''
    bash ${./.}/run.sh --dev ${../../nest/dev.qml} ${../../user/quickshell} \
      ${../../user/hypr/bindings.lua} ${../../defaults/hypr/rescue.lua} \
      ${pkgs.quickshell}/lib/qt-6/qml ${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml
    touch $out
  ''
