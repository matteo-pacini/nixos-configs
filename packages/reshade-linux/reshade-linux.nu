# Install ReShade into Wine / Proton games and keep its shaders up to date.
#
# ReShade and d3dcompiler_47 come pinned from the Nix store ($env.RESHADE_DIST);
# shader repositories are cloned into MAIN_PATH at runtime. Games get symlinks
# into MAIN_PATH, so re-running `update` upgrades every installed game at once.
#
# The MAIN_PATH layout matches kevinlekiller/reshade-steam-proton, so games set
# up with that script keep working.

const COMMON_DLLS = [dxgi d3d9 d3d11 d3d8 ddraw dinput8 opengl32]
const DEFAULT_REPOS = "https://github.com/CeeJayDK/SweetFX|sweetfx-shaders;https://github.com/martymcmodding/qUINT|martymc-shaders;https://github.com/BlueSkyDefender/AstrayFX|astrayfx-shaders;https://github.com/prod80/prod80-ReShade-Repository|prod80-shaders;https://github.com/crosire/reshade-shaders|reshade-shaders|slim;https://github.com/martymcmodding/iMMERSE|immerse-shaders;https://github.com/EndlesslyFlowering/ReShade_HDR_shaders|lilium-hdr-shaders;https://github.com/AlucardDH/dh-reshade-shaders|dh-shaders;https://github.com/FransBouma/OtisFX|otisfx-shaders;https://github.com/Fubaxiusz/fubax-shaders|fubax-shaders;https://github.com/Matsilagi/RSRetroArch|rsretroarch-shaders"
# Shader repos are pulled at most this often unless `update` is run explicitly.
const UPDATE_INTERVAL = 4hr
const CATEGORY_ORDER = [Setup Colour Tone HDR Anti-aliasing Sharpen Clean-up Light Depth Film Stylise Retro Tools]

# --- output helpers ----------------------------------------------------------

def header [text: string] {
    print $"\n(ansi magenta_bold)▌ ($text)(ansi reset)"
}

def info [text: string] { print $"  (ansi cyan)•(ansi reset) ($text)" }
def ok [text: string] { print $"  (ansi green_bold)✔(ansi reset) ($text)" }
def warn [text: string] { print $"  (ansi yellow_bold)!(ansi reset) (ansi yellow)($text)(ansi reset)" }

def fail [text: string] {
    error make --unspanned { msg: $"(ansi red_bold)($text)(ansi reset)" }
}

def confirm [question: string, --default-no] {
    let choices = if $default_no { [No Yes] } else { [Yes No] }
    ($choices | input list $"(ansi white_bold)($question)(ansi reset)") == "Yes"
}

# --- paths & state -----------------------------------------------------------

def main-path [] {
    let xdg = $env.XDG_DATA_HOME? | default ($env.HOME | path join .local share)
    $env.MAIN_PATH? | default ($xdg | path join reshade) | path expand --no-symlink
}

def dist [] {
    $env.RESHADE_DIST? | default "" | if ($in | is-empty) { fail "RESHADE_DIST is not set; run the packaged reshade-linux wrapper." } else { $in }
}

# Wine maps Z: to /, which Proton keeps too.
def wine-path [p: string] { $"Z:($p | str replace --all '/' '\')" }

def installs-file [] { main-path | path join installs.json }

def load-installs [] {
    let f = installs-file
    if ($f | path exists) { open $f } else { [] }
}

def save-installs [rows: list] { $rows | to json | save --force (installs-file) }

def shader-repos [] {
    $env.SHADER_REPOS? | default $DEFAULT_REPOS | split row ";" | where $it != "" | each {|spec|
        let parts = $spec | split row "|"
        { url: $parts.0, name: ($parts | get 1? | default ($parts.0 | path basename)), branch: ($parts | get 2? | default "") }
    }
}

# --- ReShade + d3dcompiler ---------------------------------------------------

# Copy (not link) from the store: game symlinks into /nix/store would dangle
# after the next garbage collection.
def sync-runtime [] {
    let main = main-path
    let version = $env.RESHADE_VERSION_PINNED
    for variant in [{ dir: $version, src: reshade, link: latest } { dir: $"($version)_Addon", src: reshade-addon, link: latest_Addon }] {
        let target = $main | path join reshade $variant.dir
        let src = dist | path join $variant.src
        let fresh = not ($target | path join ReShade64.dll | path exists)
        if $fresh {
            mkdir $target
            for f in (ls $src) {
                cp --force $f.name $target
                ^chmod u+w ($target | path join ($f.name | path basename))
            }
        }
        ^ln -sfn $variant.dir ($main | path join reshade $variant.link)
        if $fresh { ok $"ReShade ($variant.dir) installed" }
    }
    for arch in [32 64] {
        let src = dist | path join d3dcompiler_47 $"d3dcompiler_47.dll.($arch)"
        let dst = $main | path join $"d3dcompiler_47.dll.($arch)"
        if not ($dst | path exists) or ((open --raw $src | hash sha256) != (open --raw $dst | hash sha256)) {
            cp --force $src $dst
            chmod u+w $dst
            ok $"d3dcompiler_47 \(($arch)-bit\) updated"
        }
    }
}

# --- shaders -----------------------------------------------------------------

def update-repos [--force] {
    let main = main-path
    let stamp = $main | path join LASTUPDATED
    let now = date now | format date "%s" | into int
    let last = if ($stamp | path exists) { open $stamp | str trim | into int } else { 0 }
    let stale = $force or ($now - $last) > ($UPDATE_INTERVAL / 1sec)
    let base = $main | path join ReShade_shaders
    mkdir $base

    let results = shader-repos | par-each --keep-order {|repo|
        let dir = $base | path join $repo.name
        let res = if ($dir | path exists) {
            if $stale { do { ^git -C $dir pull --ff-only --quiet } | complete | insert action pulled } else { { exit_code: 0, action: cached, stderr: "" } }
        } else {
            let branch = if ($repo.branch | is-empty) { [] } else { [--branch $repo.branch] }
            do { ^git clone --quiet --depth 1 ...$branch $repo.url $dir } | complete | insert action cloned
        }
        let commit = if ($dir | path join .git | path exists) { ^git -C $dir log -1 --format=%h·%cs | str trim } else { "" }
        {
            repo: $repo.name
            status: (if $res.exit_code == 0 { $"(ansi green)($res.action)(ansi reset)" } else { $"(ansi red)failed(ansi reset)" })
            commit: $commit
            effects: (if ($dir | path exists) { glob $"($dir)/Shaders/**/*.fx" | length } else { 0 })
            error: ($res.stderr | str trim | lines | last 1 | str join)
        }
    }
    if $stale { $now | save --force $stamp }
    let results = if ($results | all {|r| $r.error | is-empty }) { $results | reject error } else { $results }
    print ($results | table --index false)
}

# Matches a technique header with its optional annotation block. OtisFX wraps
# the block in `#if __RESHADE__ >= 40000 … #endif`; RadiantGI opens the #if
# before `technique` and closes it after the block. Either directive is
# captured (pre/post) so the rewrite can put it back and keep them balanced.
def technique-regex [name: string] {
    '(?s)(?P<whole>technique\s+(?P<technique>' + $name + ')\s*(?P<pre>#if[^\n]*\n\s*)?(?:<(?P<ann>.*?)>)?\s*(?P<post>#endif[^\n]*\n\s*)?\{)'
}

# Inject friendly ui_label / ui_tooltip annotations; the technique identifier is
# left alone so presets (which store Technique@File.fx) still resolve.
def label-source [text: string, file: string, labels: record] {
    $labels | transpose key val | where {|r| $r.key | str ends-with $"@($file)" } | reduce --fold $text {|entry, src|
        let technique = $entry.key | split row "@" | first
        let label = $"($entry.val.cat): ($entry.val.name)"
        let matches = $src | parse --regex (technique-regex $technique)
        if ($matches | is-empty) { return $src }
        let ann = $matches.0.ann | default ""
        let ann = if ($ann =~ 'ui_label\s*=') {
            $ann | str replace --regex 'ui_label\s*=\s*"[^"]*"' $'ui_label = "($label)"'
        } else { $' ui_label = "($label)";($ann)' }
        let ann = if ($entry.val.tip? | is-not-empty) and not ($ann =~ 'ui_tooltip\s*=') {
            $'($ann) ui_tooltip = "($entry.val.tip)";'
        } else { $ann }
        $src | str replace --all $matches.0.whole $"technique ($technique)\n($matches.0.pre)<($ann) >\n($matches.0.post){"
    }
}

# Rebuild ReShade_shaders/Merged from scratch: first repo in SHADER_REPOS wins
# on duplicate paths, External_shaders comes last. A later .fx whose file name
# was already merged from another folder is skipped too, since ReShade and its
# presets identify effects by file name alone. Plain files are symlinked;
# labelled .fx files are written as copies.
def merge-shaders [] {
    let main = main-path
    let merged = $main | path join ReShade_shaders Merged
    let labels = open (dist | path join labels.nuon)
    let labelled_files = $labels | columns | each { split row "@" | last } | uniq
    rm --recursive --force $merged
    mkdir ($merged | path join Shaders) ($merged | path join Textures)

    let sources = (shader-repos | each {|r| $main | path join ReShade_shaders $r.name }) | append ($main | path join External_shaders)
    mut seen = {}
    for src in $sources {
        for kind in [Shaders Textures] {
            let root = $src | path join $kind
            if not ($root | path exists) { continue }
            for f in (glob $"($root)/**/*" --no-dir) {
                let rel = $kind | path join ($f | path relative-to $root)
                let name = $f | path basename
                let effect_key = if ($name | str ends-with ".fx") { $"fx:($name)" } else { $rel }
                if $rel in $seen or $effect_key in $seen { continue }
                $seen = $seen | insert $rel true | upsert $effect_key true
                let dst = $merged | path join $rel
                mkdir ($dst | path dirname)
                if $kind == Shaders and $name in $labelled_files {
                    label-source (open --raw $f | decode utf-8) $name $labels | save --force $dst
                } else {
                    ^ln -s $f $dst
                }
            }
        }
    }
    # Loose .fx files dropped straight into External_shaders.
    for f in (glob $"($main)/External_shaders/*.fx" --no-dir) {
        let dst = $merged | path join Shaders ($f | path basename)
        if not ($dst | path exists) { ^ln -s $f $dst }
    }
    let n = glob $"($merged)/Shaders/**/*.fx" | length
    ok $"Merged ($n) effect files, ($labelled_files | length) with readable labels"
}

# Search paths need the trailing \** or ReShade skips subfolders such as
# Merged/Shaders/SweetFX.
def ensure-ini [] {
    let main = main-path
    let ini = $main | path join ReShade.ini
    let shaders = wine-path ($main | path join ReShade_shaders Merged Shaders)
    let textures = wine-path ($main | path join ReShade_shaders Merged Textures)
    if not ($ini | path exists) {
        [
            "[GENERAL]"
            $"EffectSearchPaths=($shaders)\\**"
            $"TextureSearchPaths=($textures)\\**"
            "PresetPath=.\\ReShadePreset.ini"
            ""
            "[INPUT]"
            "KeyOverlay=36,0,0,0"
            ""
            "[OVERLAY]"
            "TutorialProgress=4"
            ""
        ] | str join "\n" | save $ini
        ok $"Created ($ini)"
        return
    }
    let text = open --raw $ini | decode utf-8
    let fixed = $text
        | str replace --regex --multiline '^(EffectSearchPaths=.*\\Merged\\Shaders)\s*$' '${1}\**'
        | str replace --regex --multiline '^(TextureSearchPaths=.*\\Merged\\Textures)\s*$' '${1}\**'
    if $fixed != $text {
        $fixed | save --force $ini
        ok "ReShade.ini search paths made recursive (SweetFX and other subfolders were not loading)"
    }
}

def refresh [--force] {
    let main = main-path
    header $"Data in ($main)"
    mkdir ($main | path join External_shaders)
    sync-runtime
    header "Shader repositories"
    update-repos --force=$force
    merge-shaders
    ensure-ini
}

# --- game discovery ----------------------------------------------------------

def steam-root [] {
    [~/.local/share/Steam ~/.steam/steam ~/.var/app/com.valvesoftware.Steam/.local/share/Steam]
        | path expand | where { path join steamapps | path exists } | get 0?
}

def steam-games [] {
    let root = steam-root
    if $root == null { return [] }
    let vdf = $root | path join steamapps libraryfolders.vdf
    let libs = if ($vdf | path exists) {
        open --raw $vdf | decode utf-8 | parse --regex '"path"\s+"(?P<p>[^"]+)"' | get p
    } else { [$root] }
    $libs | uniq | each {|lib|
        glob $"($lib)/steamapps/appmanifest_*.acf" | each {|acf|
            let txt = open --raw $acf | decode utf-8
            let field = {|k| $txt | parse --regex ('"' + $k + '"\s+"(?P<v>[^"]*)"') | get v.0? | default "" }
            { name: (do $field name), appid: (do $field appid), dir: ($lib | path join steamapps common (do $field installdir)) }
        }
    } | flatten | where {|g| ($g.dir | path exists) and not ($g.name =~ '^(Proton|Steam Linux Runtime|Steamworks Common)') } | sort-by name
}

const EXE_NOISE = '(?i)(unins|crash|redist|setup|vc_?redist|dxsetup|dotnet|easyanticheat|battleye|be_service|cefprocess|helper|install)'

def game-exes [dir: string] {
    glob $"($dir)/**/*.{exe,EXE}" --depth 5 | where {|e| not (($e | path basename) =~ $EXE_NOISE) }
        | each {|e| { exe: ($e | path relative-to $dir), size: (ls $e | get 0.size) } }
        | sort-by size --reverse
}

def pe-arch [exe: string] {
    let head = open --raw $exe | first 4096
    let pe = $head | bytes at 60..63 | into int --endian little
    let machine = $head | bytes at ($pe + 4)..($pe + 5) | into int --endian little
    if $machine == 0x8664 { 64 } else if $machine == 0x14c { 32 } else { fail $"($exe) is not a recognisable PE executable" }
}

# Imported DLL names appear as plain strings in the PE import table.
def guess-dll [exe: string, arch: int] {
    let found = do { ^grep -aoiE 'd3d(8|9|10|11|12)\.dll|dxgi\.dll|opengl32\.dll|vulkan-1\.dll' $exe } | complete | get stdout | str lowercase | lines | uniq
    let api = if ("d3d12.dll" in $found) or ("d3d11.dll" in $found) or ("dxgi.dll" in $found) or ("d3d10.dll" in $found) { "dxgi" } else if "d3d9.dll" in $found { "d3d9" } else if "d3d8.dll" in $found { "d3d8" } else if "opengl32.dll" in $found { "opengl32" } else if $arch == 64 { "dxgi" } else { "d3d9" }
    { dll: $api, imports: $found }
}

# Returns { dir, exe, arch, name }.
def pick-game [] {
    let games = steam-games
    let manual = { name: "Enter a path manually…", appid: "", dir: "" }
    let choice = if ($games | is-empty) { $manual } else {
        $games | append $manual | input list --fuzzy --display name $"(ansi white_bold)Which game?(ansi reset)"
    }
    if $choice == null { fail "Cancelled." }
    let dir = if ($choice.dir | is-empty) {
        input $"(ansi white_bold)Game folder or .exe path: (ansi reset)" | str trim | path expand
    } else { $choice.dir }
    if ($dir | path type) == file { return { dir: ($dir | path dirname), exe: $dir, arch: (pe-arch $dir), name: ($dir | path basename), appid: "" } }
    if not ($dir | path exists) { fail $"($dir) does not exist." }
    let exes = game-exes $dir
    if ($exes | is-empty) { fail $"No .exe found under ($dir)." }
    let exe = if ($exes | length) == 1 { $exes.0.exe } else {
        let pick = $exes | input list --fuzzy $"(ansi white_bold)Which executable does the game run? \(largest first\)(ansi reset)"
        if $pick == null { fail "Cancelled." }
        $pick.exe
    }
    let full = $dir | path join $exe
    { dir: ($full | path dirname), exe: $full, arch: (pe-arch $full), name: (if ($choice.dir | is-empty) { $exe } else { $choice.name }), appid: $choice.appid }
}

# --- install / uninstall -----------------------------------------------------

# Symlink, refusing to clobber a real file the game shipped with.
def place-link [target: string, link: string] {
    if ($link | path exists --no-symlink) and (($link | path type) != symlink) {
        fail $"($link) exists and is not a symlink; refusing to overwrite it."
    }
    ^ln -sfn $target $link
}

def link-names [dll: string, preset: string] {
    [$"($dll).dll" d3dcompiler_47.dll ReShade_shaders ReShade.ini] | append (if ($preset | is-empty) { [] } else { [$preset] })
}

def do-install [game: record, dll: string, addon: bool, preset: string] {
    let main = main-path
    let latest = if $addon { "latest_Addon" } else { "latest" }
    let links = [
        [($main | path join reshade $latest $"ReShade($game.arch).dll") $"($dll).dll"]
        [($main | path join $"d3dcompiler_47.dll.($game.arch)") d3dcompiler_47.dll]
        [($main | path join ReShade_shaders) ReShade_shaders]
        [($main | path join ReShade.ini) ReShade.ini]
    ] | append (if ($preset | is-empty) { [] } else { [[($main | path join $preset) $preset]] })
    for l in $links { place-link $l.0 ($game.dir | path join $l.1) }

    let record = { name: $game.name, appid: $game.appid, dir: $game.dir, dll: $dll, arch: $game.arch, addon: $addon, preset: $preset, installed: (date now | format date "%F %T") }
    save-installs (load-installs | where dir != $game.dir | append $record)

    let overrides = $"WINEDLLOVERRIDES=\"d3dcompiler_47=n;($dll)=n,b\""
    header "Done"
    ok $"Linked ReShade($game.arch) as ($dll).dll in ($game.dir)"
    print ""
    print $"  (ansi white_bold)Steam launch options:(ansi reset)"
    print $"    (ansi cyan_bold)($overrides) %command%(ansi reset)"
    print $"  (ansi white_bold)Other launchers:(ansi reset) set (ansi cyan)($overrides)(ansi reset) in the environment."
    print $"  Press (ansi yellow_bold)Home(ansi reset) in game to open the ReShade overlay."
}

# Install ReShade into a game folder (or pick a Steam game interactively).
def "main install" [
    path?: string    # Game folder or .exe; omit to choose from Steam libraries
    --dll: string    # DLL name to load ReShade as (dxgi, d3d9, opengl32, …); detected if omitted
    --addon          # Use the add-on enabled ReShade build (single-player games only)
    --preset: string = "" # Preset file in MAIN_PATH to link into the game folder
    --yes (-y)       # Accept detected defaults without prompting
] {
    let game = if $path == null { pick-game } else {
        let p = $path | path expand
        let exe = if ($p | path type) == file { $p } else {
            let rel = game-exes $p | get 0?.exe
            if $rel == null { fail $"No .exe in ($p)" }
            $p | path join $rel
        }
        { dir: ($exe | path dirname), exe: $exe, arch: (pe-arch $exe), name: ($exe | path basename), appid: "" }
    }
    let guess = guess-dll $game.exe $game.arch
    header $"($game.name)"
    info $"Executable: ($game.exe | path relative-to ($game.dir | path dirname))"
    info $"Architecture: ($game.arch)-bit"
    if ($guess.imports | is-not-empty) { info $"Graphics imports: ($guess.imports | str join ', ')" }
    if "vulkan-1.dll" in $guess.imports {
        warn "This game imports Vulkan. A DLL override only catches its D3D/OpenGL path; Vulkan-only games need a Vulkan layer (try vkBasalt) instead."
    }
    let dll = if $dll != null { $dll | str replace --regex '(?i)\.dll$' '' } else if $yes { $guess.dll } else {
        let options = [$guess.dll] | append ($COMMON_DLLS | where $it != $guess.dll)
        let pick = $options | each {|d| { dll: $d, note: (if $d == $guess.dll { "detected" } else { "" }) } }
            | input list $"(ansi white_bold)Load ReShade as which DLL?(ansi reset)"
        if $pick == null { fail "Cancelled." }
        $pick.dll
    }
    if not $yes and not (confirm $"Install ReShade as ($dll).dll into ($game.dir)?") { fail "Cancelled." }
    refresh
    do-install $game $dll $addon $preset
}

# Remove ReShade links from a game folder.
def "main uninstall" [
    path?: string # Game folder; omit to choose from recorded installs
    --purge       # Also delete ReShade.log and ReShadePreset.ini
    --yes (-y)    # Do not ask for confirmation
] {
    let installs = load-installs
    let dir = if $path != null { $path | path expand } else {
        if ($installs | is-empty) { fail "No recorded installs; pass the game folder." }
        let pick = $installs | select name dll arch dir | input list --fuzzy $"(ansi white_bold)Remove ReShade from which game?(ansi reset)"
        if $pick == null { fail "Cancelled." }
        $pick.dir
    }
    let dir = if ($dir | path type) == file { $dir | path dirname } else { $dir }
    if not $yes and not (confirm $"Remove ReShade links from ($dir)?" --default-no) { fail "Cancelled." }
    let rec = $installs | where dir == $dir | get 0?
    let candidates = ($COMMON_DLLS | each { $"($in).dll" }) | append [d3dcompiler_47.dll ReShade_shaders ReShade.ini ReShade32.json ReShade64.json Shaders Textures] | append ($rec.preset? | default "" | if ($in | is-empty) { [] } else { [$in] })
    for name in $candidates {
        let p = $dir | path join $name
        if ($p | path type) == symlink { rm $p; ok $"Removed ($name)" }
    }
    if $purge {
        for name in [ReShade.log ReShadePreset.ini] {
            let p = $dir | path join $name
            if ($p | path exists) { rm $p; ok $"Deleted ($name)" }
        }
    }
    save-installs ($installs | where dir != $dir)
    warn "Remove WINEDLLOVERRIDES from the game's launch options."
}

# --- commands ----------------------------------------------------------------

# ReShade for Wine / Proton games. Run without arguments for the menu.
def main [] {
    print $"(ansi magenta_bold)ReShade for Linux(ansi reset) (ansi dark_gray)— ReShade ($env.RESHADE_VERSION_PINNED), data in (main-path)(ansi reset)"
    let actions = [
        { action: "Install", what: "Add ReShade to a game" }
        { action: "Uninstall", what: "Remove ReShade from a game" }
        { action: "Update", what: "Pull shader repos and refresh ReShade" }
        { action: "Effects", what: "Browse effects and what they do" }
        { action: "Games", what: "Games with ReShade installed" }
    ]
    let pick = $actions | input list $"(ansi white_bold)What do you want to do?(ansi reset)"
    match $pick.action? {
        "Install" => (main install)
        "Uninstall" => (main uninstall)
        "Update" => (refresh --force)
        "Effects" => (main effects)
        "Games" => (main games)
        _ => {}
    }
}

# Pull shader repositories, refresh ReShade and rebuild the merged shader folder.
def "main update" [] { refresh --force }

# List effects in the merged shader folder with their readable names.
def "main effects" [
    --json # Print the list as JSON instead of the grouped view
] {
    let merged = main-path | path join ReShade_shaders Merged Shaders
    if not ($merged | path exists) { fail "Shaders are not installed yet; run `reshade-linux update`." }
    let rows = glob $"($merged)/**/*.fx" | each {|f|
        let src = open --raw $f | decode utf-8
        $src | parse --regex (technique-regex '\w+') | each {|t|
            let ann = $t.ann | default ""
            let label = $ann | parse --regex 'ui_label\s*=\s*"(?P<l>[^"]*)"' | get l.0? | default $t.technique
            let tip = $ann | parse --regex 'ui_tooltip\s*=\s*"(?P<t>[^"]*)"' | get t.0? | default ""
            let cat = if ($label =~ '^[A-Za-z-]+: ') { $label | split row ": " | first } else { "Other" }
            { category: $cat, effect: ($label | str replace --regex '^[A-Za-z-]+: ' ''), technique: $t.technique, file: ($f | path relative-to $merged), about: ($tip | str replace --all '\n' ' ' | str trim) }
        }
    } | flatten | uniq-by technique file
    let rows = $rows | insert order {|r| $CATEGORY_ORDER | enumerate | where item == $r.category | get index.0? | default 99 } | sort-by order effect | reject order
    if $json { return ($rows | to json) }
    for group in ($rows | chunk-by {|r| $r.category }) {
        print $"\n(ansi magenta_bold)($group.0.category)(ansi reset)"
        for r in $group {
            print $"  (ansi white_bold)($r.effect)(ansi reset) (ansi dark_gray)($r.technique)@($r.file | path basename)(ansi reset)"
            if ($r.about | is-not-empty) { print $"    ($r.about | str substring 0..140)" }
        }
    }
    print $"\n(ansi dark_gray)($rows | length) effects. In the overlay they appear as \"Category: name [file.fx]\".(ansi reset)"
}

# Games with ReShade installed by this tool.
def "main games" [] {
    let rows = load-installs
    if ($rows | is-empty) { info "No installs recorded yet."; return }
    $rows | select name dll arch addon installed dir
}
