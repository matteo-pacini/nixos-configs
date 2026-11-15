-- The desktop palette: ~/.config/desk/theme.json merged over the built-in
-- Dracula values below, returned as a table with the same keys (colours as
-- "#rrggbb", fonts as family names).
--
-- Never raises, so a broken live edit of theme.json cannot cost the desktop
-- its colours: a missing or unreadable file, a missing key, or a value of the
-- wrong form falls back to the built-in value for that key. Keys that are not
-- below are ignored.

local dracula = {
    background   = "#282a36",
    current_line = "#44475a",
    foreground   = "#f8f8f2",
    comment      = "#6272a4",
    cyan         = "#8be9fd",
    green        = "#50fa7b",
    orange       = "#ffb86c",
    pink         = "#ff79c6",
    purple       = "#bd93f9",
    red          = "#ff5555",
    yellow       = "#f1fa8c",
    font_ui      = "Fira Sans",
    font_mono    = "FiraCode Nerd Font",
}

local function valid(key, value)
    if key:sub(1, 5) == "font_" then
        return value:find("%S") ~= nil
    end
    -- Six digits only: QML reads eight as #aarrggbb, CSS and Hyprland as
    -- rrggbbaa, so an alpha would mean different things to each consumer.
    return value:find("^#%x%x%x%x%x%x$") ~= nil
end

local function read(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local text = file:read("a")
    file:close()
    return text
end

local palette = {}
for key, value in pairs(dracula) do
    palette[key] = value
end

local config = os.getenv("XDG_CONFIG_HOME")
if not config or config == "" then
    config = (os.getenv("HOME") or "") .. "/.config"
end

-- theme.json is a flat object of string values, which this pattern covers;
-- Hyprland's Lua has no JSON library. A pair it cannot match (an escaped
-- quote, a non-string value) is skipped, and so is everything after the
-- point where a truncated file ends.
local ok, text = pcall(read, config .. "/desk/theme.json")
if ok and type(text) == "string" then
    for key, value in text:gmatch('"([%w_]+)"%s*:%s*"([^"\\]*)"') do
        if dracula[key] and valid(key, value) then
            palette[key] = value
        end
    end
end

return palette
