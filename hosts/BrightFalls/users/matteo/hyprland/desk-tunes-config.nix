# The tunes service's config (desk-tunes --config; keys: desk-tunes.py): the
# model files it downloads, the GPU it composes on, and what counts as a
# game running.
{ writeText }:
let
  revision = "666ac70204440867d8c01ba4b119cc79c95b370a";

  # The class regex of the "games" window rule, read from rules.lua so the
  # hold and the rule cannot drift apart.
  rules = builtins.readFile ./user/hypr/rules.lua;
  gameRule = builtins.match ''.*name += "games",[^]]*class = \[\[([^]]+)]].*'' rules;
in
assert gameRule != null;
writeText "desk-tunes-config.json" (
  builtins.toJSON {
    model = {
      name = "ACE-Step 1.5 Turbo";
      variant = "4B Q8";
      inherit revision;
      # A file is at <base_url>/resolve/<revision>/<name>.
      base_url = "https://huggingface.co/Serveurperso/ACE-Step-1.5-GGUF";
      # sha256 and size: the LFS object of each file at that revision.
      files = [
        {
          role = "lm";
          name = "acestep-5Hz-lm-4B-Q8_0.gguf";
          sha256 = "972f91147a167f0c041f1b158d67985a82c0f6a852e68cdf70e46030cf08b1bc";
          bytes = 4457323648;
        }
        {
          role = "dit";
          name = "acestep-v15-turbo-Q8_0.gguf";
          sha256 = "288f708a61cfc241013a98a62f98ba331f83fe34d0d3559acdd9b0f6a2f7cd6b";
          bytes = 2549528000;
        }
        {
          role = "text";
          name = "Qwen3-Embedding-0.6B-Q8_0.gguf";
          sha256 = "972f23255e46adfe744a0eb9a0039f3c63988f65753b0968d776e8b27168c321";
          bytes = 784144960;
        }
        {
          role = "vae";
          name = "vae-BF16.gguf";
          sha256 = "0599862ac5d15cd308e1d2e368373aea6c02e25ebd1737ad4a4562a0901b0ef8";
          bytes = 337420928;
        }
      ];
      # The audio code the language model writes for silence.
      silence_code = 35847;
      # MemAvailable below this holds composing: the 780M's memory is system
      # RAM, and a tune took about 5.8 GiB of it.
      ram_bytes = 6 * 1024 * 1024 * 1024;
    };
    # The Radeon 780M, by PCI ids: Vulkan's device order is not stable.
    device = {
      vendor = "0x1002";
      device = "0x1900";
      label = "Radeon 780M";
    };
    game_class_regex = builtins.head gameRule;
    keep = 50;
    ahead = 2;
    duration = 180;
  }
)
