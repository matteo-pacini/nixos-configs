# desk-reload <quickshell-config-dir>: asks the running shell for one reload
# over shell.qml's "shell" IPC target. Run by Home Manager activation after a
# switch that changed ~/.config/quickshell or ~/.config/desk (README.md beside
# this file, "Activation"). Always exits 0: a shell that cannot be reloaded
# never fails activation.
#
# Quickshell does not reload by itself here: its watcher holds the files of
# the store tree it loaded, which never change, and a retargeted config link
# is not noticed; nor does it ever watch a .js file (src/core/scan.cpp,
# generation.cpp). --any-display: activation has no display variable, and qs
# would otherwise look only for instances started without one.
# The call can be refused: from the start of a reload until the generation it
# replaces is gone, two generations are alive and the shell answers "Not
# ready to accept queries yet." without calling anything. `qs ipc call` exits
# 0 all the same (Quickshell 0.3.2, IpcClient::connect in src/ipc/ipc.cpp
# drops the call's result), so only the function's own answer, `reloaded` on
# the last line, counts, and anything else is asked again every half second
# for 10 s. A non-zero exit is no shell at all.

[ $# -eq 1 ] || {
  echo "usage: desk-reload <quickshell-config-dir>" >&2
  exit 2
}

reload_shell() { # config dir
  local out tries=0
  while out=$(timeout 10 qs ipc --any-display -p "$1" call shell reload 2>&1); do
    if [ "${out##*$'\n'}" = reloaded ]; then
      echo "desk-reload: quickshell: reloaded"
      return 0
    fi
    tries=$((tries + 1))
    [ "$tries" -lt 20 ] || break
    sleep 0.5
  done
  echo "desk-reload: quickshell: not reloaded: $(tr '\n' ' ' <<<"$out")"
}

reload_shell "$1"
