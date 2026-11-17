# The token panel's helper, `desk-tokens` (protocol: desk-tokens.py).
#
# The price table, desk-tokens-prices.json, is built in as the default for
# --prices.
{ writers }:
writers.writePython3Bin "desk-tokens"
  {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  }
  (
    builtins.replaceStrings [ "@prices@" ] [ "${./desk-tokens-prices.json}" ] (
      builtins.readFile ./desk-tokens.py
    )
  )
