{
  writeShellApplication,
  wireplumber,
  pipewire,
  jq,
  libnotify,
}:
# Sets the next Modi 2 sink (stereo, then the surround sinks from
# hosts/BrightFalls/audio/surround.nix) as the default output and shows a
# notification naming it.
writeShellApplication {
  name = "audio-output-cycle";
  runtimeInputs = [
    wireplumber
    pipewire
    jq
    libnotify
  ];
  text = ''
    order=(
      alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo
      effect_input.virtual-surround-atmos
      effect_input.virtual-surround-dtshx
    )

    sinks=$(pw-dump | jq -c '[.[] | select(.info.props."media.class" == "Audio/Sink")
      | {id, name: .info.props."node.name", desc: .info.props."node.description"}]')
    sink() { jq -c --arg n "$1" 'first(.[] | select(.name == $n)) // empty' <<<"$sinks"; }

    # Replacing the previous notification keeps repeated presses from stacking.
    id_file="''${XDG_RUNTIME_DIR:-/tmp}/audio-output-cycle.id"
    notify() {
      local id
      id=$(cat "$id_file" 2>/dev/null || echo 0)
      notify-send --transient --app-name=Sound --icon=audio-headphones \
        --replace-id="$id" --print-id "Audio output" "$1" >"$id_file"
    }

    # The surround sinks only play through the Modi, so without it there is
    # nothing worth switching to.
    if [[ -z "$(sink "''${order[0]}")" ]]; then
      notify "Modi 2 isn't connected"
      exit 0
    fi

    current=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | sed -n 's/.*node\.name = "\(.*\)"/\1/p')
    start=-1
    for i in "''${!order[@]}"; do
      [[ "''${order[$i]}" == "$current" ]] && start=$i
    done

    for step in $(seq 1 "''${#order[@]}"); do
      target=$(sink "''${order[$(((start + step) % ''${#order[@]}))]}")
      [[ -n "$target" ]] && break
    done

    wpctl set-default "$(jq -r .id <<<"$target")"
    notify "$(jq -r .desc <<<"$target")"
  '';
}
