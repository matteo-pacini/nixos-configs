# Code Completion Handbook

Local fill-in-the-middle (FIM) completion in Neovim, replacing GitHub
Copilot. Every host runs its own model; nothing leaves the machine.

Two halves, both wired through Home Manager so they apply to Linux and
Darwin from one option set:

| Half | Option | Module |
|------|--------|--------|
| Server | `custom.code-completion-model` | `modules/home-manager/code-completion-model.nix` |
| Editor | `custom.nvf.completion` | `modules/home-manager/nvf.nix` |

The server is `llama-server` from `llama-cpp`, bound to `127.0.0.1:8012`.
The client is `llama.vim`, the plugin from the llama.cpp authors, which
talks to the server's `/infill` endpoint and keeps a ring buffer of extra
context chunks from the rest of your open buffers.

**Services start disabled.** The weights are a large, mostly idle memory
reservation, so bring the server up for a session that needs it rather
than holding it permanently. See [Commands](#commands).

## Selection

| Host | Hardware | Backend | Model | Quant | Weights | Ctx |
|------|----------|---------|-------|-------|---------|-----|
| Nexus | Quadro P2000, 5 GB | cuda (cc 6.1) | `ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF` | Q8_0 | 3.29 GB | 16k |
| BrightFalls | RX 6800 XT, 16 GB | vulkan | `bartowski/Qwen2.5-Coder-14B-GGUF` | Q4_K_M | 8.37 GB | 32k |
| NightSprings | M1 Max, 64 GB unified | metal | `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` | Q4_K_M | 18.56 GB | 32k |
| WorkLaptop | M4 Pro, 24 GB unified | metal | `QuantFactory/Qwen2.5-Coder-7B-GGUF` | Q4_K_M | 4.68 GB | 32k |
| CauldronLake | — | — | not enabled | — | — | — |

All four use a `q8_0` KV cache and a 300 second idle sleep.

## Why these models

**FIM is the hard constraint.** Ordinary chat models cannot do this job:
completion needs a model trained on fill-in-the-middle, with the
`fim_prefix` / `fim_suffix` / `fim_middle` tokens exercised during
training. That rules out most of what is on Hugging Face and it is why
the repos above are **base** models, not Instruct tunes — the instruct
tunes drop the FIM behaviour.

**Qwen3-Coder only exists in large sizes.** The official lineup is
`Qwen3-Coder-30B-A3B-Instruct`, `Qwen3-Coder-Next` (79.7B total, MoE) and
`Qwen3-Coder-480B-A35B-Instruct`. There is no dense 1.5B/3B/7B/14B
equivalent — the smaller "Qwen3-Coder" repos on HF are community
fine-tunes. The smallest official option is 30B-A3B, and at Q4_K_M that
file is 18.56 GB, which only NightSprings can hold. Hence Qwen3-Coder on
NightSprings and Qwen2.5-Coder everywhere else: the 2.5 generation
remains the only FIM-trained family with small dense sizes.

Qwen3 general models (4B/8B) carry FIM tokens in their vocabulary, but
whether those tokens were actually trained on
[was asked officially and never answered](https://github.com/QwenLM/Qwen3/discussions/1277).
Not a foundation for keystroke-latency completion.

**30B-A3B is a Mixture-of-Experts model** activating ~3B parameters per
token, so on NightSprings it runs far faster than its 18.56 GB footprint
suggests. llama.cpp ships a `--fim-qwen-30b-default` preset pointing at
exactly this model, which is the upstream confirmation that its FIM works.

**Nexus is the odd one out at Q8_0.** Below roughly 3B parameters, Q4
costs more accuracy than the memory it saves. 3B at Q8_0 (3.29 GB) beats
3B at Q4_K_M on a card this small, and 7B at Q4_K_M (4.68 GB) would leave
no room for the KV cache and compute buffers inside 5120 MiB.

## Quantisation

Two independent knobs.

**Weights** — `model.quant`, matched case-insensitively against the
filenames in the repo. llama.cpp falls back to the first file in the repo
if nothing matches, so a typo degrades quietly rather than failing.
Q4_K_M is the default and the right choice from 7B up.

**KV cache** — `kvCacheType`, applied to both K and V. Accepted values
are `f32 f16 bf16 q8_0 q4_0 q4_1 iq4_nl q5_0 q5_1`; note there are no
k-quants here. llama.cpp's own default is `f16`; we use `q8_0`, which
halves the cache at negligible quality cost. **Avoid `q4_0`** — it
degrades exactly the token-level precision FIM depends on.

This is not a rounding error at the larger sizes. Rough per-token K+V at
`f16`, from the published model configs — `llama-server` prints the exact
figures at load:

| Model | f16 @ 32k | q8_0 @ 32k |
|-------|-----------|------------|
| 1.5B | ~0.9 GB | ~0.5 GB |
| 7B | ~1.8 GB | ~0.9 GB |
| 14B | ~6 GB | ~3.2 GB |

A quantised V cache requires flash attention. The default `-fa auto`
enables it automatically, so this is handled — but an explicit `-fa off`
in `extraFlags` alongside a quantised cache is a hard error.

## Backends

`acceleration` selects the llama.cpp build: `cuda`, `vulkan`, `metal`, or
`null` for the package default (CPU on Linux, Metal on Darwin). Metal is
already the default on Darwin, so `"metal"` adds no override — it pins
down what the host expects and lets the module's assertions catch a
mismatch.

**Nexus needs `cudaCapabilities = [ "6.1" ]`.** nixpkgs builds CUDA
kernels for `75;80;86;89;90;100;103;120;121` — Turing and newer. The
P2000 is Pascal, compute capability 6.1, so a stock `cudaSupport = true`
build would contain no kernels it can run. The option rewrites
`CMAKE_CUDA_ARCHITECTURES` to `61`.

CUDA 12.9 still supports `sm_61`, but deprecated. A future nixpkgs bump
to CUDA 13 drops Pascal entirely and this breaks; the escape hatch is
`acceleration = "vulkan"`, which the NVIDIA 580 driver supports fine on
this card.

**BrightFalls pins `device = "Vulkan0"`.** The 780M iGPU also advertises
Vulkan, so without this llama.cpp may pick it over the 6800 XT:

```
Vulkan0: AMD Radeon RX 6800 XT (RADV NAVI21) (16368 MiB, 14798 MiB free)
Vulkan1: AMD Radeon 780M Graphics (RADV PHOENIX) (16976 MiB, 16888 MiB free)
```

Note the iGPU reports the larger total — it is addressing system RAM, not
dedicated VRAM, so size is not a safe way to tell the two apart. Re-check
the numbering with `--list-devices` if the hardware changes; enumeration
order is stable in practice but not guaranteed.

## Commands

### Linux (Nexus, BrightFalls)

```bash
systemctl --user start   code-completion-model
systemctl --user stop    code-completion-model
systemctl --user status  code-completion-model
journalctl --user -u code-completion-model -f
```

`systemctl --user enable` does not stick — Home Manager rewrites the
`default.target.wants` symlinks on every activation. To start on login,
set `autoStart = true` in the host's user config.

### Darwin (NightSprings, WorkLaptop)

The agent is bootstrapped into the `gui` domain under the label
`org.nix-community.home.code-completion-model`:

```bash
launchctl kickstart gui/$(id -u)/org.nix-community.home.code-completion-model
launchctl print    gui/$(id -u)/org.nix-community.home.code-completion-model
launchctl kill SIGTERM gui/$(id -u)/org.nix-community.home.code-completion-model
```

### Checking it works

```bash
curl -s http://127.0.0.1:8012/health     # {"status":"ok"} once weights are loaded
curl -s http://127.0.0.1:8012/props      # active model and context size
curl -s http://127.0.0.1:8012/slots      # per-slot KV cache state
llama-server --list-devices              # backend device names, for `device`
```

`llama-server` is not on `PATH` unless the module is enabled for that
host. To check devices before then, from the repo root:

```bash
nix-shell -E 'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux; in p.mkShell { packages = [ (p.llama-cpp.override { vulkanSupport = true; }) ]; }' --run 'llama-server --list-devices'
```

Swap the override for `cudaSupport = true` on an NVIDIA host. This builds
the same derivation the host config pins, so nothing is wasted.

**First start downloads the weights** — up to 18.56 GB on NightSprings —
so `/health` will not answer until that finishes. Watch the logs. Weights
land in `$XDG_CACHE_HOME/llama.cpp` (`~/.cache/llama.cpp`), outside the
Nix store, and are reused across restarts and rebuilds.

### In Neovim

Suggestions appear as ghost text automatically as you type.

| Key | Action |
|-----|--------|
| `<C-y>` | Accept full suggestion |
| `<C-g>` | Accept one line |
| `<leader>ll]` | Accept one word |
| `<C-j>` / `<C-k>` | Cycle suggestions |
| `<leader>llf` | Trigger manually |
| `<leader>lld` | Toggle the debug pane |

`<Tab>` and `<S-Tab>` are **not** used — nvf binds those to nvim-cmp for
next/previous item, so llama.vim's defaults for accept-full and
accept-line are remapped to `<C-y>` and `<C-g>`.

llama.vim renders performance stats inline next to each suggestion:
context used vs maximum, ring buffer chunks held and evicted, prompt and
generated token counts, and generation time. That readout is the fastest
way to tell whether the server is actually being hit.

## Idle sleep

`sleepIdleSeconds` defaults to 300. After five idle minutes the server
tears the model down and frees its memory; the next request reloads it
from scratch. llama.cpp's own default is no sleep at all.

The cost is paid on the first keystroke after a break: the reload, plus a
full prompt reprocess, because the wake also discards the KV cache and
llama.vim's ring context. Set `sleepIdleSeconds = null` on a host where
nothing else contends for the memory and you would rather keep it warm.

## Options

| Option | Default | Notes |
|--------|---------|-------|
| `enable` | `false` | |
| `autoStart` | `false` | Start on login |
| `acceleration` | `metal` on Darwin, `null` on Linux | `cuda` / `vulkan` / `metal` / `null` |
| `cudaCapabilities` | `null` | e.g. `[ "6.1" ]` for pre-Turing cards |
| `model.repo` | — | Hugging Face GGUF repo, base model |
| `model.quant` | `Q4_K_M` | |
| `contextSize` | `32768` | |
| `kvCacheType` | `q8_0` | `null` leaves llama.cpp's `f16` |
| `host` | `127.0.0.1` | |
| `port` | `8012` | What llama.vim expects |
| `device` | `null` | For multi-GPU hosts |
| `sleepIdleSeconds` | `300` | `null` keeps the model resident |
| `extraFlags` | `[ ]` | Appended last |

Fixed, not exposed: `--batch-size 1024`, `--ubatch-size 1024`,
`--cache-reuse 256`. These come from llama.cpp's own `--fim-qwen-*`
presets — oversized batches because FIM reprocesses prefix and suffix on
every keystroke, and a cache-reuse floor so KV shifting salvages the
unchanged prefix instead of recomputing it.

## Changing the model

Point `model.repo` at another GGUF repo and rebuild. Requirements:

- A **base** model, not an Instruct tune.
- FIM-trained. The [llama.vim HF collection](https://huggingface.co/collections/ggml-org/llamavim-6720fece33898ac10544ecf9)
  is the safe list.
- Weights plus KV cache must fit the budget in the table above.

To try one without a rebuild, stop the service and run `llama-server` by
hand on the same port — llama.vim will not know the difference:

```bash
llama-server -hf <repo>:<quant> --port 8012 --ctx-size 32768 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --batch-size 1024 --ubatch-size 1024 --cache-reuse 256
```

## Gotchas

- **`nix build` needs new files `git add`ed.** Applies to this module
  like anything else in the flake.
- **`/health` returns nothing on first start** until the download
  finishes. Not a failure.
- **Model is not in the Nix store.** Weights are fetched at runtime into
  `~/.cache/llama.cpp`; `nix-collect-garbage` will not touch them and a
  rollback will not restore them.
- **CUDA builds from source on Nexus** — the `cc 6.1` variant matches no
  binary cache. It lands in the self-hosted attic cache afterward.
- **Quantised V without flash attention is fatal.** Do not put `-fa off`
  in `extraFlags` while `kvCacheType` is a quantised type.
