# Unlocks a Hyprland session whose lock screen died or no longer takes the
# password. Run it from a text console: Ctrl+Alt+F4, log in, `desk-unlock`,
# then `exit` and Ctrl+Alt+F3. README.md, "Lock screen", has the background.

echo "Hyprland says locked: $(hyprctl --instance 0 locked 2>&1)"

# Ends a hung lock screen. "not loaded" means it is already gone.
systemctl --user stop desk-lock 2>&1 || true

# Hyprland refuses while a lock client still holds the lock.
out=$(hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()' 2>&1) || true
echo "unlock: $out"

case "$out" in
*refusing*)
  systemctl --user kill -s KILL desk-lock 2>&1 || true
  # The lock's exact command line, so nothing else that mentions the
  # config directory is matched.
  pkill -KILL -f '/bin/quickshell -n -p .*/quickshell/lock\.qml' || true
  sleep 1
  echo "unlock, second try: $(hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()' 2>&1)"
  ;;
esac

echo "Hyprland says locked: $(hyprctl --instance 0 locked 2>&1)"
echo "If that says false: type exit, then press Ctrl+Alt+F3."
