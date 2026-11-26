# desk-nest-caption: overlays a caption track on a recording. Re-runnable:
# the recording is never changed; edit the track and run again.
#
# usage: desk-nest-caption <recording> <captions.txt> <out.mp4> [fps]
#
# captions.txt, one item per line, # comments; times in seconds of the
# recording (before padding); pad, title and end lines are split with shell
# quoting, a caption's text is the rest of its line as written:
#   pad <before> <after>                    hold the first/last frame that long
#   title <start> <end> "<title>" "<sub>"   full-frame card (times may be < 0
#   end   <start> <end> "<title>" "<sub>"   to sit in the pre-pad)
#   <start> <end> [bottom|top|center] <text...>
# fps: output rate (default 60); a variable-rate input is conformed to it.
#
# The Nix wrapper sets, before this text: captions_py (captions.py beside
# this file) and fonts (Fira Sans's truetype directory).
[ $# -ge 3 ] || {
  sed -n '3,12p' "$0" >&2
  exit 2
}
in=$1 track=$2 out=$3 fps=${4:-60}
export CAPTION_FONT_REGULAR=$fonts/FiraSans-Regular.ttf
export CAPTION_FONT_MEDIUM=$fonts/FiraSans-Medium.ttf
export CAPTION_FONT_SEMIBOLD=$fonts/FiraSans-SemiBold.ttf
read -r W H < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$in" | tr x ' ')
work=$(mktemp -d "${TMPDIR:-/tmp}/caption.XXXXXX")
trap 'rm -rf "$work"' EXIT
python3 -I "$captions_py" "$track" "$work" "$W" "$H" "$fps"
mapfile -t inputs <"$work/inputs"
ffmpeg -hide_banner -loglevel error -y -i "$in" "${inputs[@]}" \
  -/filter_complex "$work/filter" -map '[out]' -an \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart -r "$fps" "$out"
ffprobe -v error -show_entries stream=width,height,r_frame_rate,nb_frames:format=duration -of default=nw=1 "$out"
