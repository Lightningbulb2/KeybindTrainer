-- Behaviour test: runs the REAL hook files and modules against mocked engine
-- pieces. Stock Lua 5.0, run from the mod folder:
--     lua50 extras/test_logic.lua
-- Proves the decision logic and the hook plumbing; it cannot prove anything
-- about how the UI looks or what the real engine does (see README).

dofile('extras/harness.lua')
Harness.Mount('/mods/KeybindTrainer', '.')
local MOD = '/mods/KeybindTrainer'

local Say = print   -- the mod's print() is mocked below; keep a real one for the report
local passed, failed = 0, 0
local function Check(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        Say('  FAIL  ' .. name)
    end
end

--------------------------------------------------------------------------------
-- mocked engine
--------------------------------------------------------------------------------
local world

local function Fresh()
    Harness.Reset()
    _G.KeybindTrainerPath = nil
    _G.__active_mods = { { uid = 'other', location = '/mods/Other' }, { uid = 'keybind-trainer-v1', location = MOD } }

    world = {
        replay = false, focusArmy = 1, selection = {}, prints = {},
        keymap = { Q = 'patrol', A = 'reclaim', W = 'builders', M = 'upgrades',
                   Tab = 'pause_unit', Z = 'toggle_repeat_build' },
        notified = {}, prefs = {}, keyActionsSet = 0, notifyThrows = false,
    }
    local actions = {
        builders = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Builders")' },
        upgrades = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Upgrades")' },
        patrol = { action = 'StartCommandMode order RULEUCC_Patrol' },
    }
    local groups = {
        Builders = { 'Land_Factory', 'T1_Engineer' },
        Land_Factory = { 'ueb0101' },
        T1_Engineer = { 'uel0105', 'legacy1', 'legacy2' },
        Upgrades = { '_upgrade' },
    }

    SessionIsReplay = function() return world.replay end
    GetFocusArmy = function() return world.focusArmy end
    GetSelectedUnits = function() return world.selection end
    print = function(s) table.insert(world.prints, s) end
    __blueprints = {
        ueb0101 = { Description = '<LOC ueb0101_desc>Land Factory', CategoriesHash = { STRUCTURE = true, FACTORY = true }, General = { UpgradesFrom = 'none' } },
        uel0105 = { Description = '<LOC uel0105_desc>Engineer', CategoriesHash = { MOBILE = true, ENGINEER = true }, General = { UpgradesFrom = 'none' } },
        ueb1202 = { Description = '<LOC ueb1202_desc>Mass Extractor (T2)', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'ueb1103', UpgradesFromBase = 'ueb1103' } },
        xxx0000 = { Description = 'Unbound thing', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'none' } },
        legacy1 = { Description = 'Old style', Categories = { 'MOBILE', 'LAND' }, General = { UpgradesFrom = 'none' } },
        legacy2 = { Description = 'Old style building', Categories = { 'STRUCTURE', 'DEFENSE' }, General = { UpgradesFrom = 'none' } },
    }

    local O = Harness.overrides
    O['/lua/keymap/keymapper.lua'] = {
        GetCurrentKeyMap = function() return world.keymap end,
        GetKeyActions = function() return actions end,
        SetUserKeyAction = function(name, def) world.keyActionsSet = world.keyActionsSet + 1 world.lastKeyAction = { name = name, def = def } end,
    }
    O['/lua/keymap/unitkeygroups.lua'] = { unitkeygroups = groups }
    O['/lua/ui/help/tooltips.lua'] = { Tooltips = { patrol = { title = '<LOC t>Patrol', keyID = 'patrol' },
                                                     attack_move = { title = '<LOC t>Attack Move', keyID = 'attackmove' } } }
    O['/lua/keymap/properkeynames.lua'] = { properKeyNames = { Tab = '<LOC p>Tab' } }
    O['/lua/user/prefs.lua'] = {
        GetFromCurrentProfile = function(k) return world.prefs[k] end,
        SetToCurrentProfile = function(k, v) world.prefs[k] = v end,
    }
    O[MOD .. '/modules/feedback.lua'] = {
        Notify = function(control, key, label)
            if world.notifyThrows then error('boom') end
            table.insert(world.notified, { key = key, label = label, control = control })
        end,
        Destroy = function() world.destroyed = true end,
    }
    O[MOD .. '/modules/panel.lua'] = {
        Create = function(fn, enabled, n) world.pillCreated = true world.pillToggle = fn world.pill = { enabled = enabled, n = n } end,
        Refresh = function(enabled, n) world.pill = { enabled = enabled, n = n } end,
        Rebuild = function() world.rebuilt = (world.rebuilt or 0) + 1 end,
        SetEditing = function(on) world.editing = on end,
        SetUIHidden = function() world.uiHidden = (world.uiHidden or 0) + 1 end,
        Destroy = function() world.panelDestroyed = true end,
    }
end

local function Click(btn, mods) return btn:OnClick(mods) end
local LEFT = { Left = true }
local RIGHT = { Right = true }

local function Order(helpText, opts)
    opts = opts or {}
    local o = { _data = { helpText = helpText }, disabled = opts.disabled, checked = opts.checked, called = 0 }
    function o:IsDisabled() return self.disabled end
    function o:IsChecked() return self.checked end
    o.OnClick = function(self, m) self.called = self.called + 1 end
    return o
end

--------------------------------------------------------------------------------
Say('== trainer: orders')
Fresh()
local T = import(MOD .. '/modules/trainer.lua')

local b = Order('patrol')
Check('left click on bound order is refused', T.CheckOrder(b, LEFT) == true)
Check('...and the note names the key and the order', world.notified[1] and world.notified[1].key == 'Q' and world.notified[1].label == 'Patrol')
Check('...and it was counted', T.GetBlockedCount() == 1)
Check('right click passes', T.CheckOrder(Order('patrol'), RIGHT) == false)
Check('no modifiers table (not a mouse click) passes', T.CheckOrder(Order('patrol'), nil) == false)
Check('already-active command order (cancel) passes', T.CheckOrder(Order('patrol', { checked = true }), LEFT) == false)
Check('disabled button passes', T.CheckOrder(Order('patrol', { disabled = true }), LEFT) == false)
-- the return fire / hold fire / ground fire toggle: never refused, even with a key bound
world.keymap.bracket = 'mode'
import(MOD .. '/modules/keybinds.lua').Invalidate()
Check('the fire-mode toggle is never refused, even with a key bound to it', T.CheckOrder(Order('mode'), LEFT) == false)
Check('...nor under any of its state names', T.CheckOrder(Order('mode_hold_fire'), LEFT) == false and T.CheckOrder(Order('mode_hold_ground'), LEFT) == false and T.CheckOrder(Order('mode_return_fire'), LEFT) == false)
Check('...and no key is ever reported for it', import(MOD .. '/modules/keybinds.lua').GetOrderKey('mode') == nil and import(MOD .. '/modules/keybinds.lua').GetOrderKey('mode_hold_fire') == nil)
Check('other orders are unaffected', T.CheckOrder(Order('patrol'), LEFT) == true)
world.keymap.bracket = nil
import(MOD .. '/modules/keybinds.lua').Invalidate()
Check('order with no key bound passes', T.CheckOrder(Order('move'), LEFT) == false)
Check('unknown helpText passes', T.CheckOrder(Order('some_mod_order'), LEFT) == false)
Check('control without _data passes', T.CheckOrder({}, LEFT) == false)
Check('toggle-type order that is "checked" is still refused (the click IS the action)',
      (function() world.keymap.T = 'toggle_shield' import(MOD .. '/modules/keybinds.lua').Invalidate()
                  return T.CheckOrder(Order('toggle_shield', { checked = true }), LEFT) end)() == true)

local am = Order('attack_move')
Check('attack move is refused with its Alt + Right Click hint', T.CheckOrder(am, LEFT) == true and world.notified[table.getn(world.notified)].key == 'Alt + Right Click')
local cfg = import(MOD .. '/modules/config.lua').Config
cfg.Lock.AttackMove = false
Check('attack move can be unlocked in config', T.CheckOrder(Order('attack_move'), LEFT) == false)
cfg.Lock.AttackMove = true
cfg.Lock.Orders = false
Check('Lock.Orders = false disables order locking', T.CheckOrder(Order('patrol'), LEFT) == false)
cfg.Lock.Orders = true

Say('== trainer: gates')
world.replay = true
Check('inactive in a replay', T.CheckOrder(Order('patrol'), LEFT) == false)
world.replay = false
world.focusArmy = -1
Check('inactive while observing', T.CheckOrder(Order('patrol'), LEFT) == false)
world.focusArmy = 1
T.SetEnabled(false)
Check('inactive when switched off', T.CheckOrder(Order('patrol'), LEFT) == false)
Check('off state is saved to the profile', world.prefs.KeybindTrainer and world.prefs.KeybindTrainer.enabled == false)
T.Toggle()
Check('toggle turns it back on and saves', T.IsEnabled() == true and world.prefs.KeybindTrainer.enabled == true)
Check('the panel is refreshed on toggle', world.pill and world.pill.enabled == true)

Say('== trainer: build menu')
local item = { Data = { type = 'item', id = 'ueb0101' }, IsDisabled = function() return false end }
Check('bound hotbuild unit is refused', T.CheckBuild(item, LEFT) == true)
Check('...with key W and a readable label', world.notified[table.getn(world.notified)].key == 'W' and world.notified[table.getn(world.notified)].label == 'Build Land Factory')
Check('right click (dequeue) passes', T.CheckBuild(item, RIGHT) == false)
Check('no modifiers (build-template key path) passes', T.CheckBuild(item, nil) == false)
-- buildings vs units
Check('a UNIT (engineer from a factory) passes by default', T.CheckBuild({ Data = { type = 'item', id = 'uel0105' } }, LEFT) == false)
cfg.Lock.Units = true
Check('...and is refused once Lock.Units is on', T.CheckBuild({ Data = { type = 'item', id = 'uel0105' } }, LEFT) == true and world.notified[table.getn(world.notified)].label == 'Build Engineer')
cfg.Lock.Buildings = false
Check('Lock.Buildings = false lets a structure through', T.CheckBuild(item, LEFT) == false)
Check('...while units are still refused', T.CheckBuild({ Data = { type = 'item', id = 'uel0105' } }, LEFT) == true)
cfg.Lock.Buildings = true
cfg.Lock.Units = false
Check('classification also works from a plain Categories list (unit)', (function() cfg.Lock.Units = false return T.CheckBuild({ Data = { type = 'item', id = 'legacy1' } }, LEFT) end)() == false)
Check('classification also works from a plain Categories list (structure)', T.CheckBuild({ Data = { type = 'item', id = 'legacy2' } }, LEFT) == true)
Check('default config: units off, buildings on', cfg.Lock.Units == false and cfg.Lock.Buildings == true)
Check('unit in no bound group passes', T.CheckBuild({ Data = { type = 'item', id = 'xxx0000' } }, LEFT) == false)
Check('non-item (selection stack) passes', T.CheckBuild({ Data = { type = 'unitstack', id = 'ueb0101' } }, LEFT) == false)
Check('templates entry passes', T.CheckBuild({ Data = { type = 'templates' } }, LEFT) == false)
Check('ids are matched case-insensitively', T.CheckBuild({ Data = { type = 'item', id = 'UEB0101' } }, LEFT) == true)

world.selection = { { GetBlueprint = function() return { BlueprintId = 'ueb1103', General = { UpgradesTo = 'ueb1202', UpgradesFromBase = 'ueb1103' } } end } }
Check('default config: upgrades are NOT locked', cfg.Lock.Upgrades == false)
Check('...so upgrading the selected building by mouse is free', T.CheckBuild({ Data = { type = 'item', id = 'ueb1202' } }, LEFT) == false)
cfg.Lock.Upgrades = true
cfg.Lock.Buildings = false
Check('Upgrades is its own switch: on, with Buildings off, the upgrade is refused', T.CheckBuild({ Data = { type = 'item', id = 'ueb1202' } }, LEFT) == true)
cfg.Lock.Buildings = true
Check('...and constructing a building is a different switch (Buildings on, Upgrades on: both locked)', T.CheckBuild(item, LEFT) == true)
cfg.Lock.Upgrades = false
Check('Upgrades off, Buildings on: construction still locked, upgrade free', T.CheckBuild(item, LEFT) == true and T.CheckBuild({ Data = { type = 'item', id = 'ueb1202' } }, LEFT) == false)
cfg.Lock.Upgrades = true
Check('upgrade of the selection is refused', T.CheckBuild({ Data = { type = 'item', id = 'ueb1202' } }, LEFT) == true)
Check('...showing the upgrade key and label', world.notified[table.getn(world.notified)].key == 'M' and world.notified[table.getn(world.notified)].label == 'Upgrade to Mass Extractor (T2)')
world.keymap.M = nil
import(MOD .. '/modules/keybinds.lua').Invalidate()
Check('upgrade with no upgrade key (and not in a group) passes', T.CheckBuild({ Data = { type = 'item', id = 'ueb1202' } }, LEFT) == false)
world.keymap.M = 'upgrades'
import(MOD .. '/modules/keybinds.lua').Invalidate()
cfg.Lock.Upgrades = false

Say('== trainer: panel buttons')
local pb = { IsDisabled = function() return false end }
Check('pause is refused with Tab', T.CheckPanel(pb, LEFT, 'pause') == true and world.notified[table.getn(world.notified)].key == 'Tab' and world.notified[table.getn(world.notified)].label == 'Pause')
Check('repeat build is refused with Z', T.CheckPanel(pb, LEFT, 'repeat_build') == true and world.notified[table.getn(world.notified)].key == 'Z')
cfg.Lock.Pause = false
Check('Lock.Pause = false disables it', T.CheckPanel(pb, LEFT, 'pause') == false)
cfg.Lock.Pause = true
Check('unknown panel name passes', T.CheckPanel(pb, LEFT, 'nonsense') == false)

Say('== fail open')
world.notifyThrows = true
Check('an error while giving feedback lets the click through', T.CheckOrder(Order('patrol'), LEFT) == false)
world.notifyThrows = false
Check('and it works again afterwards', T.CheckOrder(Order('patrol'), LEFT) == true)
SessionIsReplay = function() error('engine exploded') end
Check('an engine error in the gate lets the click through', T.CheckOrder(Order('patrol'), LEFT) == false)
SessionIsReplay = function() return world.replay end

Say('== lifecycle')
Fresh()
world.prefs.KeybindTrainer = { enabled = false }
T = import(MOD .. '/modules/trainer.lua')
T.Init(false)
Check('Init restores a saved OFF state', T.IsEnabled() == false)
Check('Init creates the panel', world.pillCreated == true)
Check('no startup message when off', table.getn(world.prints) == 0)
Check('toggle key action registered once', world.keyActionsSet == 1 and world.lastKeyAction.name == 'toggle_keybind_trainer')
Check('...pointing at this module with the resolved path', string.find(world.lastKeyAction.def.action, MOD .. '/modules/trainer.lua', 1, true) ~= nil and world.lastKeyAction.def.category == 'mods')
world.prefs.UserKeyActions = { toggle_keybind_trainer = world.lastKeyAction.def }
T.Init(false)
Check('...and not re-written when already there', world.keyActionsSet == 1)
world.pillCreated = false
T.Init(true)
Check('no panel in a replay', world.pillCreated == false)
T.Destroy()
Check('Destroy tears the panel and the feedback down', world.destroyed == true and world.panelDestroyed == true)
Fresh()
T = import(MOD .. '/modules/trainer.lua')
T.Init(false)
Check('Init exposes the panel hooks for the ReUI options window', type(_G.KeybindTrainerRebuild) == 'function' and type(_G.KeybindTrainerSetEditing) == 'function')
_G.KeybindTrainerSetEditing(true)
Check('...the editing hook reaches the panel', world.editing == true)
_G.KeybindTrainerSetEditing(false)
Check('...and switches it off again', world.editing == false)
_G.KeybindTrainerRebuild()
Check('...the rebuild hook reaches the panel', world.rebuilt == 1)
T.OnUIHiddenChanged()
Check('screen capture mode is passed to the panel', world.uiHidden == 1)
T.Destroy()
Check('Destroy removes the hooks', _G.KeybindTrainerRebuild == nil and _G.KeybindTrainerSetEditing == nil)
Fresh()
T = import(MOD .. '/modules/trainer.lua')
T.Init(false)
Check('startup message when on', table.getn(world.prints) == 1)
world.pillToggle()
Check('the panel callback toggles the trainer', T.IsEnabled() == false)

--------------------------------------------------------------------------------
Say('== hook: orders.lua')
Fresh()
local calls = { setAvailable = 0, setLayout = 0 }
local items = { Order('patrol'), Order('move'), Order('reclaim') }
local noData = { OnClick = function() end }
local grid = {
    GetDimensions = function() return 2, 2 end,
    GetItem = function(self, col, row)
        local list = { { items[1], items[2] }, { items[3], noData } }
        return list[row][col]
    end,
}
local env = { controls = { orderButtonGrid = grid },
              SetAvailableOrders = function() calls.setAvailable = calls.setAvailable + 1 end,
              SetLayout = function() calls.setLayout = calls.setLayout + 1 end }
Harness.LoadInto('hook/lua/ui/game/orders.lua', env)
env.SetAvailableOrders({}, {}, {})
Check('original SetAvailableOrders still runs', calls.setAvailable == 1)
Check('order buttons got wrapped', items[1].KbtWrapped and items[2].KbtWrapped and items[3].KbtWrapped)
Check('entries without _data are left alone', not noData.KbtWrapped)
items[1]:OnClick(LEFT)
Check('click on a bound order never reaches the original behaviour', items[1].called == 0)
Check('mod path is resolved from __active_mods on first use', _G.KeybindTrainerPath == MOD)
items[1]:OnClick(RIGHT)
Check('right click reaches the original behaviour', items[1].called == 1)
items[2]:OnClick(LEFT)
Check('unbound order reaches the original behaviour', items[2].called == 1)
items[3]:OnClick(LEFT)
Check('reclaim (A) is refused', items[3].called == 0)
local wrapped = items[1].OnClick
env.SetAvailableOrders({}, {}, {})
Check('re-running does not wrap twice', items[1].OnClick == wrapped)
env.SetLayout('left')
Check('SetLayout also wraps and still calls the original', calls.setLayout == 1 and items[1].OnClick == wrapped)

-- a new button object appears after a rebuild (as the real game does every selection change)
local fresh = Order('patrol')
items[1] = fresh
env.SetAvailableOrders({}, {}, {})
fresh:OnClick(LEFT)
Check('buttons created by a rebuild are wrapped too', fresh.KbtWrapped and fresh.called == 0)

env.controls = nil
local before = calls.setAvailable
env.SetAvailableOrders({}, {}, {})
Check('missing controls table is tolerated (original still ran)', calls.setAvailable == before + 1)
env.controls = { orderButtonGrid = { GetDimensions = function() error('grid not ready') end } }
env.SetLayout('x')
Check('an error while wrapping is swallowed (original still ran)', calls.setLayout == 2)

Say('== hook: construction.lua')
Fresh()
local built = {}
local item2 = { Data = { type = 'item', id = 'ueb0101' } }
local free = { Data = { type = 'item', id = 'xxx0000' } }
local cenv = { controls = { extraBtn1 = { OnClick = function() end }, extraBtn2 = { OnClick = function() end } },
               OnClickHandler = function(button, modifiers) table.insert(built, button) end,
               CreateExtraControls = function(t) end }
Harness.LoadInto('hook/lua/ui/game/construction.lua', cenv)
cenv.OnClickHandler(item2, LEFT)
Check('bound build icon is swallowed', table.getn(built) == 0)
cenv.OnClickHandler(free, LEFT)
Check('unbound build icon reaches the original handler', table.getn(built) == 1)
cenv.OnClickHandler(item2, RIGHT)
Check('right click reaches the original handler', table.getn(built) == 2)
cenv.OnClickHandler(item2, nil)
Check('template-key call (no modifiers) reaches the original handler', table.getn(built) == 3)

local pressed = { 0, 0 }
cenv.controls.extraBtn1.OnClick = function() pressed[1] = pressed[1] + 1 end
cenv.controls.extraBtn2.OnClick = function() pressed[2] = pressed[2] + 1 end
cenv.controls.extraBtn1.IsDisabled = function() return false end
cenv.controls.extraBtn2.IsDisabled = function() return false end
cenv.CreateExtraControls('construction')
cenv.controls.extraBtn1:OnClick(LEFT)
cenv.controls.extraBtn2:OnClick(LEFT)
Check('repeat-build and pause buttons are locked in the construction tab', pressed[1] == 0 and pressed[2] == 0)
cenv.controls.extraBtn1:OnClick(RIGHT)
Check('...but not for a right click', pressed[1] == 1)
local w2 = cenv.controls.extraBtn2.OnClick
cenv.CreateExtraControls('construction')
cenv.CreateExtraControls('selection')
Check('pause button is never wrapped twice', cenv.controls.extraBtn2.OnClick == w2)

-- 'selection' tab: extraBtn1 is "save template" (no keybind) and must not be locked
cenv.controls.extraBtn1.OnClick = function() pressed[1] = pressed[1] + 100 end
cenv.controls.extraBtn1.KbtWrapper = nil
cenv.CreateExtraControls('selection')
cenv.controls.extraBtn1:OnClick(LEFT)
Check('save-template button is left alone in the selection tab', pressed[1] == 101)

Say('== hook: hotkeylabels.lua (keymap refresh)')
Fresh()
local initRuns = 0
local henv = { init = function() initRuns = initRuns + 1 end }
Harness.LoadInto('hook/lua/keymap/hotkeylabels.lua', henv)
T = import(MOD .. '/modules/trainer.lua')
Check('Q locks patrol', T.CheckOrder(Order('patrol'), LEFT) == true)
world.keymap = { Q = nil, X = 'patrol' }
Check('stale cache before the keymap is confirmed', T.CheckOrder(Order('patrol'), LEFT) == true and world.notified[table.getn(world.notified)].key == 'Q')
henv.init()
Check('original init still runs', initRuns == 1)
Check('after init() the new key is shown', T.CheckOrder(Order('patrol'), LEFT) == true and world.notified[table.getn(world.notified)].key == 'X')
world.keymap = {}
henv.init()
Check('unbinding the key unlocks the button', T.CheckOrder(Order('patrol'), LEFT) == false)

Say('== hook: gamemain.lua')
Fresh()
local started, destroyedFns = 0, {}
local hideCalls = {}
local genv = { CreateUI = function(isReplay) started = started + 1 end,
               HideGameUI = function(state) table.insert(hideCalls, state) end,
               AddOnUIDestroyedFunction = function(fn) table.insert(destroyedFns, fn) end }
Harness.LoadInto('hook/lua/ui/game/gamemain.lua', genv)
genv.CreateUI(false)
Check('original CreateUI runs and the trainer starts', started == 1 and world.pillCreated == true)
Check('teardown is registered', table.getn(destroyedFns) == 1)
genv.HideGameUI('off')
Check('HideGameUI still runs the original and tells the panel', hideCalls[1] == 'off' and world.uiHidden == 1)
_G.KeybindTrainerPath = nil
genv.HideGameUI(nil)
Check('...and never errors before the mod path is known', table.getn(hideCalls) == 2)
_G.KeybindTrainerPath = MOD
destroyedFns[1]()
Check('teardown destroys the panel and the feedback', world.destroyed == true and world.panelDestroyed == true)
Harness.overrides[MOD .. '/modules/feedback.lua'] = nil
Harness.modules[MOD .. '/modules/trainer.lua'] = nil
Harness.overrides[MOD .. '/modules/trainer.lua'] = { Init = function() error('startup bug') end }
genv.CreateUI(false)
Check('a startup failure does not break the game UI', started == 2)

Say(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
