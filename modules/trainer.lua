--******************************************************************************
--** Keybind Trainer -- modules/trainer.lua
--**
--** The decision logic. The hook files call the Check* functions from inside a
--** button's click handler; a result of true means "swallow this click".
--**
--** Design rules:
--**   * Fail OPEN. Any error in here means the click goes through as normal.
--**     The mod must never be the reason an order is not given.
--**   * Only a plain LEFT click is ever refused. Right clicks (dequeue, target
--**     priority, distribute assist, dock damaged ...) do things that have their
--**     own meaning and no matching key, so they are left alone. (One exception:
--**     ReUI's engineer build menu starts a build on ANY button, so there the
--**     right button is refused as well, see opts.anyButton.)
--**   * Only buttons whose action has a key bound RIGHT NOW are refused.
--**   * Calls with no modifiers table are not mouse clicks (the build-template
--**     keys call the construction click handler directly) and always pass.
--**   * Does nothing in replays or while observing.
--******************************************************************************

local Path = rawget(_G, 'KeybindTrainerPath') or '/mods/KeybindTrainer'
local Config = import(Path .. '/modules/config.lua').Config
local Keybinds = import(Path .. '/modules/keybinds.lua')

local PREF_KEY = 'KeybindTrainer'
local KEY_ACTION_NAME = 'toggle_keybind_trainer'

local State = {
    enabled = Config.EnabledByDefault,
    blocked = 0,
    started = false,
    errorLogged = false,
}

--- Order buttons that just start a command mode. Clicking one that is already
--- active cancels the mode, which is not "using the order", so that passes.
local COMMAND_MODE_ORDERS = {
    attack = true, move = true, patrol = true, assist = true, reclaim = true,
    capture = true, repair = true, transport = true, fire_nuke = true,
    fire_tactical = true, teleport = true, ferry = true, sacrifice = true,
    special_action = true, attack_move = true,
}

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function LogOnce(where, err)
    if not State.errorLogged then
        State.errorLogged = true
        WARN('KeybindTrainer: error in ' .. where .. ' (clicks are passed through): ' .. tostring(err))
    end
end

local properNames = nil
local function Translate(token)
    if properNames == nil then
        local ok, names = pcall(function()
            return import('/lua/keymap/properkeynames.lua').properKeyNames
        end)
        properNames = (ok and names) or false
    end
    local raw = properNames and properNames[token]
    if raw then
        return LOC(raw)
    end
    return nil
end

local function ShowKey(combo)
    return Keybinds.Display(combo, Translate)
end

local function IsPlayingForReal()
    if SessionIsReplay() then
        return false
    end
    if GetFocusArmy() == -1 then
        return false
    end
    return true
end

--- Master gate shared by every check.
function IsActive()
    return State.enabled and IsPlayingForReal()
end

local function PrettyName(helpText)
    local ok, tips = pcall(function() return import('/lua/ui/help/tooltips.lua').Tooltips end)
    local tip = ok and tips and tips[helpText]
    if tip and tip.title then
        return LOC(tip.title)
    end
    -- 'toggle_shield' -> 'Toggle shield'
    local words = string.gsub(helpText, '_', ' ')
    return string.upper(string.sub(words, 1, 1)) .. string.sub(words, 2)
end

local function UnitName(id)
    local bp = __blueprints and __blueprints[id]
    if bp and bp.Description then
        return LOC(bp.Description)
    end
    return tostring(id)
end

--- Same test construction.lua's click handler uses to decide that clicking an
--- item means "upgrade the selected structure" rather than "build it".
local function IsUpgradeOfSelection(id)
    local bp = __blueprints and __blueprints[id]
    local general = bp and bp.General
    if not general or not general.UpgradesFrom or general.UpgradesFrom == 'none' then
        return false
    end

    local selection = GetSelectedUnits()
    if not selection then
        return false
    end
    for _, unit in ipairs(selection) do
        local ubp = unit:GetBlueprint()
        if general.UpgradesFrom == ubp.BlueprintId or general.UpgradesFrom == ubp.General.UpgradesTo then
            return true
        end
        local base = general.UpgradesFromBase
        if base and base ~= 'none' then
            if base == ubp.BlueprintId or base == ubp.General.UpgradesFromBase then
                return true
            end
        end
    end
    return false
end

--- Refuse a click: count it, tell the player, update the panel.
local function Refuse(control, combo, label)
    State.blocked = State.blocked + 1
    import(Path .. '/modules/feedback.lua').Notify(control, ShowKey(combo), label)
    import(Path .. '/modules/panel.lua').Refresh(State.enabled, State.blocked)
end

--- A real, enabled, plain-left-click on a control that is not disabled.
local function IsLiveLeftClick(control, modifiers)
    if not modifiers or not modifiers.Left then
        return false
    end
    if control.IsDisabled and control:IsDisabled() then
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- checks (return true = swallow the click)
--------------------------------------------------------------------------------

local function CheckOrderUnsafe(control, modifiers)
    if not Config.Lock.Orders or not IsActive() then
        return false
    end
    if not IsLiveLeftClick(control, modifiers) then
        return false
    end

    local data = control._data
    local helpText = data and data.helpText
    if not helpText or Keybinds.IsNeverLocked(helpText) then
        return false
    end

    -- Clicking an order that is already active only cancels it.
    if COMMAND_MODE_ORDERS[helpText] and control.IsChecked and control:IsChecked() then
        return false
    end

    if helpText == 'attack_move' then
        -- Not in the keymap: FAF hard-wires it to Alt + Right Click.
        if not Config.Lock.AttackMove then
            return false
        end
        Refuse(control, 'Alt-RightClick', PrettyName(helpText))
        return true
    end

    local combo = Keybinds.GetOrderKey(helpText)
    if not combo then
        return false
    end
    Refuse(control, combo, PrettyName(helpText))
    return true
end

--- Is this blueprint a structure? (Units are the mobile things factories build.)
local function IsStructure(id)
    local bp = __blueprints and __blueprints[id]
    if not bp then
        return true
    end
    if bp.CategoriesHash then
        return bp.CategoriesHash.STRUCTURE and true or false
    end
    for _, category in ipairs(bp.Categories or {}) do
        if category == 'STRUCTURE' then
            return true
        end
    end
    return false
end

--- The shared decision for any "start building / upgrading this blueprint" click,
--- whichever panel it came from (the base game's build menu or ReUI's).
---@param control Control  the clicked button (where the note appears)
---@param id string        blueprint id
---@param modifiers table  the click's modifiers (nil: not a mouse click, never refused)
---@param opts table|nil   anyButton: refuse any mouse button, not only the left one
---                        upgrade:   this click is always a structure upgrade
local function CheckBuildIdUnsafe(control, id, modifiers, opts)
    if not IsActive() or not modifiers or type(id) ~= 'string' then
        return false
    end
    if not (opts and opts.anyButton) and not modifiers.Left then
        return false
    end
    if control.IsDisabled and control:IsDisabled() then
        return false
    end

    local upgrade = (opts and opts.upgrade) or IsUpgradeOfSelection(id)

    -- Three separate switches: upgrading a building, constructing a building, and
    -- units. An upgrade is always of a structure and is never "construction".
    if upgrade then
        if not Config.Lock.Upgrades then
            return false
        end
    elseif IsStructure(id) then
        if not Config.Lock.Buildings then
            return false
        end
    elseif not Config.Lock.Units then
        return false
    end

    local combo = Keybinds.GetBuildKey(id)
    local label = nil
    if upgrade then
        local upgradeCombo = Keybinds.GetUpgradeKey()
        if upgradeCombo then
            combo = upgradeCombo
        end
        label = 'Upgrade to ' .. UnitName(id)
    end
    if not combo then
        return false
    end

    Refuse(control, combo, label or ('Build ' .. UnitName(id)))
    return true
end

local function CheckBuildUnsafe(button, modifiers)
    local item = button.Data
    if type(item) ~= 'table' or item.type ~= 'item' then
        return false
    end
    return CheckBuildIdUnsafe(button, item.id, modifiers, nil)
end

local PANEL_LABELS = { pause = 'Pause', repeat_build = 'Repeat build' }
local PANEL_LOCKS = { pause = 'Pause', repeat_build = 'RepeatBuild' }

local function CheckPanelUnsafe(control, modifiers, which)
    if not Config.Lock[PANEL_LOCKS[which]] or not IsActive() then
        return false
    end
    if not IsLiveLeftClick(control, modifiers) then
        return false
    end
    local combo = Keybinds.GetPanelKey(which)
    if not combo then
        return false
    end
    Refuse(control, combo, PANEL_LABELS[which])
    return true
end

--- Order panel button clicked. Returns true if the click must be swallowed.
function CheckOrder(control, modifiers)
    local ok, result = pcall(CheckOrderUnsafe, control, modifiers)
    if not ok then LogOnce('CheckOrder', result) return false end
    return result
end

--- Construction menu icon clicked.
function CheckBuild(button, modifiers)
    local ok, result = pcall(CheckBuildUnsafe, button, modifiers)
    if not ok then LogOnce('CheckBuild', result) return false end
    return result
end

--- A build/upgrade click from a panel other than the base game's (ReUI's).
--- `opts` as in CheckBuildIdUnsafe.
function CheckBuildItem(control, id, modifiers, opts)
    local ok, result = pcall(CheckBuildIdUnsafe, control, id, modifiers, opts)
    if not ok then LogOnce('CheckBuildItem', result) return false end
    return result
end

--- Pause / repeat-build button clicked. `which` is 'pause' or 'repeat_build'.
function CheckPanel(control, modifiers, which)
    local ok, result = pcall(CheckPanelUnsafe, control, modifiers, which)
    if not ok then LogOnce('CheckPanel', result) return false end
    return result
end

--------------------------------------------------------------------------------
-- on / off
--------------------------------------------------------------------------------

local function SavePrefs()
    pcall(function()
        import('/lua/user/prefs.lua').SetToCurrentProfile(PREF_KEY, { enabled = State.enabled })
    end)
end

local function LoadPrefs()
    local ok, saved = pcall(function()
        return import('/lua/user/prefs.lua').GetFromCurrentProfile(PREF_KEY)
    end)
    if ok and type(saved) == 'table' and saved.enabled ~= nil then
        State.enabled = saved.enabled and true or false
    end
end

function SetEnabled(enabled)
    State.enabled = enabled and true or false
    SavePrefs()
    pcall(function()
        import(Path .. '/modules/panel.lua').Refresh(State.enabled, State.blocked)
    end)
    if State.enabled then
        print('Keybind Trainer: ON - buttons that have a keybind are locked')
    else
        print('Keybind Trainer: OFF')
    end
end

--- Also the target of the optional "Toggle Keybind Trainer" keybinding.
function Toggle()
    SetEnabled(not State.enabled)
end

function IsEnabled()
    return State.enabled
end

function GetBlockedCount()
    return State.blocked
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

--- Adds "Toggle Keybind Trainer" to the keybinding window (category Mods).
--- Written only when missing/changed so we do not touch the profile every game.
local function RegisterKeyAction()
    if not Config.RegisterKeyAction then
        return
    end
    local wanted = 'UI_Lua import("' .. Path .. '/modules/trainer.lua").Toggle()'
    local current = import('/lua/user/prefs.lua').GetFromCurrentProfile('UserKeyActions')
    local existing = current and current[KEY_ACTION_NAME]
    if existing and existing.action == wanted then
        return
    end
    import('/lua/keymap/keymapper.lua').SetUserKeyAction(KEY_ACTION_NAME, {
        action = wanted,
        category = 'mods',
    })
end

--- Called from gamemain's CreateUI, after the whole game UI exists.
function Init(isReplay)
    LoadPrefs()
    Keybinds.Invalidate()

    local ok, err = pcall(RegisterKeyAction)
    if not ok then LOG('KeybindTrainer: could not register the toggle key action: ' .. tostring(err)) end

    State.isReplay = isReplay and true or false
    -- The ReUI options window reaches the panel through these two (see options.lua).
    rawset(_G, 'KeybindTrainerRebuild', RebuildUI)
    rawset(_G, 'KeybindTrainerSetEditing', SetEditing)

    if isReplay then
        return
    end

    ok, err = pcall(function()
        import(Path .. '/modules/panel.lua').Create(Toggle, State.enabled, State.blocked)
    end)
    if not ok then LOG('KeybindTrainer: could not create the panel: ' .. tostring(err)) end

    if Config.StartupMessage and State.enabled and not State.started then
        print('Keybind Trainer is ON: buttons that have a keybind are locked. Click the panel at the top to turn it off.')
    end
    State.started = true
end

function Destroy()
    rawset(_G, 'KeybindTrainerRebuild', nil)
    rawset(_G, 'KeybindTrainerSetEditing', nil)
    pcall(function() import(Path .. '/modules/panel.lua').Destroy() end)
    pcall(function() import(Path .. '/modules/feedback.lua').Destroy() end)
end

--- Rebuild what is drawn for a setting that is only read when it is made (the
--- panel). The options window calls this through _G.KeybindTrainerRebuild.
function RebuildUI()
    local ok, err = pcall(function()
        import(Path .. '/modules/panel.lua').Rebuild()
    end)
    if not ok then LOG('KeybindTrainer: could not rebuild the panel: ' .. tostring(err)) end
end

--- ReUI's options window for us opened or closed: while it is open the panel's
--- arrow drags the panel (_G.KeybindTrainerSetEditing).
function SetEditing(on)
    local ok, err = pcall(function()
        import(Path .. '/modules/panel.lua').SetEditing(on)
    end)
    if not ok then LOG('KeybindTrainer: could not switch panel editing: ' .. tostring(err)) end
end

--- The game's interface was hidden or shown again (screen capture mode): the
--- panel follows it. Called from the gamemain hook.
function OnUIHiddenChanged()
    pcall(function()
        import(Path .. '/modules/panel.lua').SetUIHidden()
    end)
end
