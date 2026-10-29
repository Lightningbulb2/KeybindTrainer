--******************************************************************************
--** Keybind Trainer -- modules/options.lua
--**
--** The settings ReUI can change, as one list: what each is called, its tooltip,
--** what kind of control it gets, and which field of config.lua it sets.
--** Main.lua and Options.lua at the mod's root are ReUI's entry points and only
--** go through this file.
--**
--** ReUI is optional. Without it nothing here runs and config.lua's own values
--** stand. With it, its saved values are written into Config when it loads us,
--** and every change after that is written straight in too. The rest of the mod
--** reads Config as it goes, so changes apply at once; only the panel is
--** built once, so changing it rebuilds it (_G.KeybindTrainerRebuild, set by the
--** trainer for the length of a game). While this mod's window is open the panel
--** can be dragged (_G.KeybindTrainerSetEditing, same).
--**
--** NOT in here, on purpose: whether the trainer is ON. That is a live in-game
--** switch (the panel, or a key you bind) remembered per profile, not a
--** preference, and two places owning it would fight.
--**
--** Written against ReUI.Options 2.0 (Main.lua requires it): option values are
--** ReactiveOptions (:Get, :Set, OnChanged:Add), and the window is
--** ReUI.Options.Add + ReUI.Options.Window with a Quick container
--** (q:OptionCheckbox ...).
--**
--** No engine imports but config.lua: ReUI may load this before the game's
--** interface exists.
--******************************************************************************

local Config = import('config.lua').Config

--- ReUI's name for the mod's options (also /mods/<n>/Options.lua).
MOD_KEY = 'KeybindTrainer'
TITLE = 'Keybind Trainer'

--- kind: 'title' (a heading), 'toggle' (a checkbox), 'number' (an integer slider).
--- path: { table in Config, field }. tip: the tooltip. rebuild: only read when the
--- panel is built, so it is rebuilt on change.
Spec = {
    { kind = 'title', label = 'What gets locked' },
    { key = 'orders', label = 'Order buttons', kind = 'toggle', path = { 'Lock', 'Orders' },
        tip = 'Move, attack, patrol, reclaim, stop, guard, toggles and the rest of the orders panel: locked while the order has a key bound. The return fire / hold fire / ground fire toggle is never locked.' },
    { key = 'attackMove', label = 'Attack Move button', kind = 'toggle', path = { 'Lock', 'AttackMove' },
        tip = 'Attack Move has no entry in the keymap: its shortcut is Alt + Right Click. Locks the button anyway so you learn that.' },
    { key = 'buildings', label = 'Building construction', kind = 'toggle', path = { 'Lock', 'Buildings' },
        tip = 'Structure icons in the build menu (engineers, the commander), once a key is bound to them. Upgrading an existing building is the next switch.' },
    { key = 'upgrades', label = 'Building upgrades', kind = 'toggle', path = { 'Lock', 'Upgrades' },
        tip = 'The upgrade icon of a building you have selected (a mass extractor to its next tier, a factory to an HQ), while the upgrade key is bound. Off by default.' },
    { key = 'units', label = 'Units in factories', kind = 'toggle', path = { 'Lock', 'Units' },
        tip = 'Unit icons in factory, gateway and carrier menus. Off by default, so queueing units with the mouse stays free.' },
    { key = 'pause', label = 'Pause button', kind = 'toggle', path = { 'Lock', 'Pause' },
        tip = 'The pause button of the construction panel, while the pause key is bound.' },
    { key = 'repeatBuild', label = 'Repeat-build button', kind = 'toggle', path = { 'Lock', 'RepeatBuild' },
        tip = 'The infinite / repeat-build button of the construction panel, while its key is bound.' },

    { kind = 'title', label = 'When you click a locked button' },
    { key = 'toast', label = 'Show the key above the button', kind = 'toggle', path = { 'Feedback', 'Toast' },
        tip = 'A small note over the button you clicked, naming the key to press instead.' },
    { key = 'toastSeconds', label = 'Seconds the note stays', kind = 'number', path = { 'Feedback', 'ToastSeconds' }, min = 1, max = 6, step = 1,
        tip = 'How long the note stays before it fades.' },
    { key = 'flash', label = 'Flash the button red', kind = 'toggle', path = { 'Feedback', 'Flash' },
        tip = 'A short red flash on the button you clicked.' },
    { key = 'sound', label = 'Play the error sound', kind = 'toggle', path = { 'Feedback', 'Sound' },
        tip = 'The game\'s standard "not allowed" blip.' },

    { kind = 'title', label = 'Panel' },
    { key = 'panel', label = 'Show the panel', kind = 'toggle', path = { 'Panel', 'Show' }, rebuild = true,
        tip = 'The small ON / OFF panel next to the game\'s menu strip, with its collapse arrow. Off hides all of it, arrow included. Click it in a game to switch the trainer on or off; hidden, you can still bind a key to "Toggle Keybind Trainer" (Keybindings, Mods).' },
    { key = 'panelFolded', label = 'Panel starts folded', kind = 'toggle', path = { 'Panel', 'StartCollapsed' },
        tip = 'Start each game with the panel folded down to just its arrow.' },
    { key = 'startup', label = 'Say so when a game starts', kind = 'toggle', path = { 'StartupMessage' },
        tip = 'One line of text at the start of a game while the trainer is on.' },
}

--- The table in Config holding an entry's field (Config itself for one-level paths).
---@param entry table
---@return table | nil
local function Owner(entry)
    if not entry.path then
        return nil
    end
    if entry.path[2] then
        return Config[entry.path[1]]
    end
    return Config
end

--- The name of an entry's field in its owner.
local function Field(entry)
    return entry.path[2] or entry.path[1]
end

--- An entry's value as ReUI shows it, from Config (config.lua's default).
---@param entry table
---@return boolean | number
function Default(entry)
    local owner = Owner(entry)
    local value = owner and owner[Field(entry)]
    if entry.kind == 'toggle' then
        return value and true or false
    end
    if type(value) ~= 'number' then
        value = entry.min
    end
    value = math.floor(value + 0.5)
    if value < entry.min then value = entry.min end
    if value > entry.max then value = entry.max end
    return value
end

--- Write a value from ReUI into Config.
---@param entry table
---@param value any
---@return boolean   # whether Config changed
function Apply(entry, value)
    local owner = Owner(entry)
    if type(owner) ~= 'table' then
        return false
    end
    local new
    if entry.kind == 'toggle' then
        new = value and true or false
    else
        if type(value) ~= 'number' or value ~= value then
            return false
        end
        if value < entry.min then value = entry.min end
        if value > entry.max then value = entry.max end
        new = value
    end
    if owner[Field(entry)] == new then
        return false
    end
    owner[Field(entry)] = new
    return true
end

--- Rebuild what is drawn, if a game is running (the trainer sets this for a game).
local function Rebuild()
    local rebuild = rawget(_G, 'KeybindTrainerRebuild')
    if rebuild then
        pcall(rebuild)
    end
end

--- ReUI's saved values into Config, and every change from now on.
---@param values table   # ReUI.Options.Mods[MOD_KEY]: key -> option
function Bind(values)
    if type(values) ~= 'table' then
        return
    end
    for _, item in ipairs(Spec) do
        -- A local of this iteration's own (Lua 5.0 closures in loops).
        local entry = item
        local option = entry.key and values[entry.key]
        if option then
            Apply(entry, option:Get())
            option.OnChanged:Add(function(changed, value)
                if Apply(entry, value) and entry.rebuild then
                    Rebuild()
                end
            end)
        end
    end
end

--- ReUI's option values, with config.lua's values as their defaults.
---@param Make? function   # ReUI.Options.OptionValue; none: plain values
---@return table
function MakeValues(Make)
    local values = {}
    for _, entry in ipairs(Spec) do
        if entry.key then
            values[entry.key] = Make and Make(Default(entry)) or Default(entry)
        end
    end
    return values
end

--- The contents of the window ReUI 2.x builds (its Quick container).
---@param q table        # OptionsContainer
---@param values table   # ReUI.Options.Mods[MOD_KEY]
function BuildWindow(q, values)
    local first = true
    for _, entry in ipairs(Spec) do
        local option = entry.key and values[entry.key]
        if entry.kind == 'title' then
            if not first then
                q:Splitter()
            end
            q:Title(entry.label)
            first = false
        elseif option then
            if entry.kind == 'toggle' then
                q:OptionCheckbox(entry.label, option)
            else
                q:OptionSlider(entry.label, option, entry.min, entry.max, entry.step)
            end
            if entry.tip then
                q:Tooltip(entry.label, entry.tip)
            end
        end
    end
    q:Splitter()
    q:Text('While this window is open, drag the panel\'s arrow along the', 12)
    q:Text('left, right or top edge of the screen to move it (a Reset', 12)
    q:Text('position button appears under it). Click the arrow to fold it.', 12)
    q:Text('The trainer itself is switched on and off from the panel.', 12)
end

--- Tell the panel (if a game is running) that the window is open, so its arrow
--- drags it, and again when the window is closed.
---@param on boolean
local function SetEditing(on)
    local set = rawget(_G, 'KeybindTrainerSetEditing')
    if set then
        pcall(set, on)
    end
end

--- ReUI destroys a window when it is closed: that is the signal.
---@param window table
function WatchWindow(window)
    SetEditing(true)
    local destroy = window.OnDestroy
    window.OnDestroy = function(self)
        SetEditing(false)
        if destroy then
            return destroy(self)
        end
    end
end

--- Put the window in ReUI's options list.
---@param Options table   # ReUI.Options
---@param values table    # ReUI.Options.Mods[MOD_KEY]
function Register(Options, values)
    Options.Add(TITLE, function(frame)
        local window = Options.Window(TITLE, function(q)
            BuildWindow(q, values)
        end)
        pcall(WatchWindow, window)
        return window
    end)
end
