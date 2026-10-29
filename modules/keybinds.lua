--******************************************************************************
--** Keybind Trainer -- modules/keybinds.lua
--**
--** Answers one question: "does this button have a key bound to it right now,
--** and if so which one?"
--**
--** Source of truth is the keymap the game is actually using
--** (KeyMapper.GetCurrentKeyMap, which falls back to the preset when the
--** player never saved their own), NOT FAF's hotkey-label tables: those only
--** exist for players who have saved a custom keymap, drop keys longer than
--** three characters, and lose the Shift modifier.
--**
--** Deliberately imports nothing at load time. hotkeylabels.lua hooks into
--** this file's cache (Invalidate) and it is reachable from construction.lua /
--** orders.lua hooks, so a top-level import here could create an import cycle.
--** Everything engine-side is imported lazily inside Rebuild().
--**
--** Lua 5.0 only: no '#', no '%', no varargs, no 'continue', no '!='.
--******************************************************************************

local cache = nil

--- Order button (its tooltip name, which is its _data.helpText) -> keymap actions
--- that do the same thing, most "basic" first. Superset of FAF's own mapping in
--- hotkeylabels.lua: unit blueprints may override a toggle's helpText (that is why
--- toggle_radar and friends are here), and the shift_ variants are listed so a
--- player who only bound those is still covered.
local TOGGLE_ALL = 'toggle_all'

ORDER_ACTIONS = {
    attack          = { 'attack', 'shift_attack' },
    move            = { 'move', 'shift_move' },
    assist          = { 'guard', 'shift_guard' },
    stop            = { 'stop', 'soft_stop', 'shift_stop' },
    patrol          = { 'patrol', 'shift_patrol' },
    repair          = { 'repair', 'shift_repair' },
    capture         = { 'capture', 'shift_capture' },
    reclaim         = { 'reclaim', 'shift_reclaim' },
    overcharge      = { 'overcharge', 'shift_overcharge' },
    teleport        = { 'teleport' },
    dive            = { 'dive', 'shift_dive' },
    transport       = { 'transport', 'shift_transport' },
    ferry           = { 'ferry', 'shift_ferry' },
    sacrifice       = { 'sacrifice' },
    dock            = { 'dock', 'shift_dock' },
    fire_tactical   = { 'launch_tactical', 'shift_launch_tactical' },
    build_tactical  = { 'build_tactical' },
    build_nuke      = { 'build_nuke' },
    fire_nuke       = { 'nuke', 'shift_nuke' },

    toggle_shield        = { 'toggle_shield', 'toggle_intelshield', TOGGLE_ALL },
    toggle_shield_dome   = { 'toggle_shield_dome', 'toggle_intelshield', TOGGLE_ALL },
    toggle_jamming       = { 'toggle_jamming', 'toggle_cloakjammingstealth', TOGGLE_ALL },
    toggle_stealth       = { 'toggle_stealth', 'toggle_cloakjammingstealth', TOGGLE_ALL },
    toggle_stealth_field = { 'toggle_stealth_field', 'toggle_cloakjammingstealth', TOGGLE_ALL },
    toggle_cloak         = { 'toggle_cloak', 'toggle_cloakjammingstealth', TOGGLE_ALL },
    toggle_intel         = { 'toggle_intel', 'toggle_intelshield', TOGGLE_ALL },
    toggle_radar         = { 'toggle_radar', 'toggle_intel', 'toggle_intelshield', TOGGLE_ALL },
    toggle_sonar         = { 'toggle_sonar', 'toggle_intel', 'toggle_intelshield', TOGGLE_ALL },
    toggle_omni          = { 'toggle_omni', 'toggle_intel', 'toggle_intelshield', TOGGLE_ALL },
    toggle_scrying       = { 'toggle_scrying', 'toggle_intel', 'toggle_intelshield', TOGGLE_ALL },
    scry_target          = { 'scry_target' },
    toggle_weapon        = { 'toggle_weapon' },
    toggle_production    = { 'toggle_production' },
    toggle_generic       = { 'toggle_generic' },
    toggle_special       = { 'toggle_special' },
}

--- Actions of the non-order buttons of the construction panel.
ACTION_LISTS = {
    pause  = { 'pause_unit', 'shift_pause_unit' },
    repeat_build = { 'toggle_repeat_build', 'shift_toggle_repeat_build' },
}

--- Buttons that are NEVER locked, whatever is bound: the return fire / hold fire /
--- ground fire toggle (its helpText is 'mode', and each of its states has a tooltip
--- named mode_...). It is a state you flip constantly in a fight.
---@param helpText string
---@return boolean
function IsNeverLocked(helpText)
    return helpText == 'mode' or string.sub(helpText, 1, 5) == 'mode_'
end

--- Compact names for keys whose engine names are long or awkward.
local SHORT = {
    Comma = ',', Period = '.', Slash = '/', Backslash = '\\', Minus = '-',
    Quote = "'", LeftBracket = '[', RightBracket = ']', Chevron = '<', Backtick = '`',
    NumPlus = 'Num +', NumMinus = 'Num -', NumStar = 'Num *', NumSlash = 'Num /',
    RightClick = 'Right Click',  -- used for Alt + Right Click (attack move), not a keymap name
}

--------------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------------

local function CountModifiers(combo)
    local n = 0
    local rest = combo
    while true do
        local s = string.find(rest, '-', 1, true)
        if not s then break end
        n = n + 1
        rest = string.sub(rest, s + 1)
    end
    return n
end

--- Is combo `a` a nicer one to show a player than combo `b`?
--- Fewer modifiers first (Q beats Shift-Q), then shorter, then alphabetical so
--- the answer never depends on table iteration order.
local function IsBetter(a, b)
    local ma = CountModifiers(a)
    local mb = CountModifiers(b)
    if ma ~= mb then
        return ma < mb
    end
    local la = string.len(a)
    local lb = string.len(b)
    if la ~= lb then
        return la < lb
    end
    return a < b
end

--- Walk a unitkeygroups group, following nested group names, collecting blueprint
--- ids (lower case) and special tokens such as '_upgrade'.
local function ExpandGroup(index, name, ids, tokens, seen)
    local lname = string.lower(name)
    if seen[lname] then
        return
    end
    seen[lname] = true

    local items = index[lname]
    if not items then
        return
    end

    for _, item in ipairs(items) do
        if type(item) == 'string' then
            local litem = string.lower(item)
            if index[litem] then
                ExpandGroup(index, item, ids, tokens, seen)
            elseif string.sub(item, 1, 1) == '_' then
                tokens[item] = true
            else
                ids[litem] = true
            end
        end
    end
end

--- Record that `combo` builds every id in `ids` (a set: id -> true).
local function ApplyIds(c, ids, combo)
    local size = 0
    for _ in pairs(ids) do
        size = size + 1
    end

    -- A unit can sit in several bound groups (a broad "cycle" group and its own
    -- narrow one). Show the key of the narrowest group: it is the most direct.
    for id in pairs(ids) do
        local cur = c.byId[id]
        if (not cur) or size < cur.size or (size == cur.size and IsBetter(combo, cur.combo)) then
            c.byId[id] = { combo = combo, size = size }
        end
    end
end

local function ApplyGroup(c, index, group, combo)
    local ids = {}
    local tokens = {}
    ExpandGroup(index, group, ids, tokens, {})

    ApplyIds(c, ids, combo)

    if tokens['_upgrade'] then
        if (not c.upgrade) or IsBetter(combo, c.upgrade) then
            c.upgrade = combo
        end
    end
end

--- ReUI.Hotbuild keeps the player's own build sets in the profile (pref
--- 'hotbuildoverhaul') and registers one key action per set, whose action string
--- is ProcessHotbuild("<name with every run of non-alphanumerics as _>").
--- Flatten one saved set into a set of ids the way ReUI.Hotbuild's Compile does;
--- template entries (tables) are not single units and are skipped.
function CollectHotbuildIds(data)
    local ids = {}
    local function Take(bp)
        if type(bp) == 'string' then
            ids[string.lower(bp)] = true
        end
    end
    for category, entries in pairs(data or {}) do
        if type(entries) == 'table' then
            if category == 'Construction' then
                for _, bps in pairs(entries) do
                    if type(bps) == 'table' then
                        for _, bp in pairs(bps) do Take(bp) end
                    end
                end
            else
                for _, bp in pairs(entries) do Take(bp) end
            end
        end
    end
    return ids
end

--- ReUI.Hotbuild's name for a key action: the set's name, formatted.
function FormatHotbuildName(name)
    return (string.gsub(name, '[^A-Za-z0-9]+', '_'))
end

--------------------------------------------------------------------------------
-- building the lookup tables
--------------------------------------------------------------------------------

--- Pure function: no engine access, so it can be tested with plain tables.
---@param keymap table   key combo -> action name        (KeyMapper.GetCurrentKeyMap)
---@param actions table  action name -> { action = str } (KeyMapper.GetKeyActions)
---@param groups table   group name -> list of ids/groups (unitkeygroups)
---@param tooltips table tooltip name -> { keyID = action } (optional)
---@param hotbuildSets table formatted ReUI.Hotbuild set name -> set of ids (optional)
function Build(keymap, actions, groups, tooltips, hotbuildSets)
    local c = { byAction = {}, byId = {}, upgrade = nil, tooltips = tooltips or {} }

    local index = {}
    for name, items in pairs(groups or {}) do
        index[string.lower(name)] = items
    end

    for combo, actionName in pairs(keymap or {}) do
        if type(combo) == 'string' and type(actionName) == 'string' then
            local prev = c.byAction[actionName]
            if (not prev) or IsBetter(combo, prev) then
                c.byAction[actionName] = combo
            end

            -- Hotbuild keys: the action string names the unit group it cycles through.
            local def = actions and actions[actionName]
            local str = type(def) == 'table' and def.action
            if type(str) == 'string' then
                local _, _, group = string.find(str, 'buildAction%("([%w_]+)"%)')
                if group then
                    ApplyGroup(c, index, group, combo)
                elseif hotbuildSets then
                    -- ReUI.Hotbuild: one of the player's own build sets.
                    local _, _, set = string.find(str, 'ProcessHotbuild%("([%w_]+)"%)')
                    if set and hotbuildSets[set] then
                        ApplyIds(c, hotbuildSets[set], combo)
                    end
                end
            end
        end
    end

    return c
end

--- The player's ReUI.Hotbuild sets as { formattedName = set of ids }, but only if
--- ReUI.Hotbuild is actually loaded this game (a leftover key action from a mod
--- that is no longer enabled does nothing, so it must not lock anything).
local function ReUIHotbuildSets()
    local reui = rawget(_G, 'ReUI')
    if not reui then
        return nil
    end
    local ok, loaded = pcall(function()
        local module = reui.Get('ReUI.Hotbuild')
        return module and module.Status == 'loaded'
    end)
    if not ok or not loaded then
        return nil
    end

    local saved = import('/lua/user/prefs.lua').GetFromCurrentProfile('hotbuildoverhaul')
    local sets = {}
    for name, data in pairs(saved or {}) do
        sets[FormatHotbuildName(name)] = CollectHotbuildIds(data)
    end
    return sets
end

--- Engine glue: read the live keymap and rebuild the cache. Fails open: if the
--- engine data cannot be read, the cache is empty and nothing gets locked.
function Rebuild()
    local ok, result = pcall(function()
        local KeyMapper = import('/lua/keymap/keymapper.lua')
        local groups = import('/lua/keymap/unitkeygroups.lua').unitkeygroups
        local tooltips = import('/lua/ui/help/tooltips.lua').Tooltips
        local sets = nil
        local setsOk, setsResult = pcall(ReUIHotbuildSets)
        if setsOk then
            sets = setsResult
        else
            LOG('KeybindTrainer: ReUI.Hotbuild sets not read: ' .. tostring(setsResult))
        end
        return Build(KeyMapper.GetCurrentKeyMap(), KeyMapper.GetKeyActions(), groups, tooltips, sets)
    end)

    if ok and result then
        cache = result
    else
        WARN('KeybindTrainer: could not read the keymap, nothing will be locked: ' .. tostring(result))
        cache = Build({}, {}, {}, {})
    end
    return cache
end

--- Forget everything; the next lookup rebuilds. Called when the keymap changes.
function Invalidate()
    cache = nil
end

local function Get()
    return cache or Rebuild()
end

--------------------------------------------------------------------------------
-- lookups (all return the raw engine combo, e.g. 'Shift-Q', or nil)
--------------------------------------------------------------------------------

local function FirstBound(c, list)
    for i = 1, table.getn(list) do
        local combo = c.byAction[list[i]]
        if combo then
            return combo
        end
    end
    return nil
end

--- Key bound to an order button, by its helpText.
function GetOrderKey(helpText)
    if not helpText or IsNeverLocked(helpText) then
        return nil
    end
    local c = Get()

    local list = ORDER_ACTIONS[helpText]
    if list then
        local combo = FirstBound(c, list)
        if combo then
            return combo
        end
    end

    -- Anything FAF adds later: its own tooltip table says which action a button is.
    local tip = c.tooltips[helpText]
    if type(tip) == 'table' and type(tip.keyID) == 'string' and tip.keyID ~= '' then
        return c.byAction[tip.keyID]
    end
    return nil
end

--- Key bound to one of the construction panel's extra buttons ('pause', 'repeat_build').
function GetPanelKey(name)
    local list = ACTION_LISTS[name]
    if not list then
        return nil
    end
    return FirstBound(Get(), list)
end

--- Key that builds (or cycles to) a unit/structure, by blueprint id.
function GetBuildKey(id)
    if type(id) ~= 'string' then
        return nil
    end
    local entry = Get().byId[string.lower(id)]
    return entry and entry.combo or nil
end

--- Key bound to the "upgrade selected structure" hotbuild action.
function GetUpgradeKey()
    return Get().upgrade
end

--------------------------------------------------------------------------------
-- display
--------------------------------------------------------------------------------

--- 'Ctrl-Shift-Q' -> 'Ctrl + Shift + Q'.
---@param combo string
---@param translate function|nil  token -> nicer name or nil (e.g. localized key names)
function Display(combo, translate)
    if not combo then
        return ''
    end

    local parts = {}
    local count = 0
    local rest = combo
    while true do
        local s = string.find(rest, '-', 1, true)
        if not s then break end
        count = count + 1
        parts[count] = string.sub(rest, 1, s - 1)
        rest = string.sub(rest, s + 1)
    end
    count = count + 1
    parts[count] = rest

    for i = 1, count do
        local token = parts[i]
        local nice = SHORT[token]
        if (not nice) and translate then
            nice = translate(token)
        end
        parts[i] = nice or token
    end

    return table.concat(parts, ' + ', 1, count)
end
