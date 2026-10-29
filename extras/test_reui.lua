-- ReUI integration test: runs the REAL Main.lua, Options.lua, modules/options.lua
-- and modules/reui.lua against a fake ReUI shaped like the real one, with
-- stand-ins for ReUI.Construction's classes. Stock Lua 5.0:
--     lua50 extras/test_reui.lua
-- (extras/test_reui_real.lua does the same with ReUI's own source files.)

dofile('extras/harness.lua')
Harness.Mount('/mods/KeybindTrainer', '.')
local MOD = '/mods/KeybindTrainer'

local Say = print
local passed, failed = 0, 0
local function Check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1 Say('  FAIL  ' .. name) end
end

local LEFT, RIGHT = { Left = true }, { Right = true }
local world

--------------------------------------------------------------------------------
-- the pieces of ReUI the mod touches
--------------------------------------------------------------------------------

--- ReUI.Options.ReactiveOption's shape (the current ReUI).
local function Reactive(default)
    local o = { value = default, listeners = {}, OnChanged = {} }
    function o:Get() return self.value end
    function o:Set(v)
        self.value = v
        for _, f in ipairs(self.listeners) do f(self, v) end
    end
    function o.OnChanged:Add(fn) table.insert(o.listeners, fn) end
    return o
end

local function FakeQ(log)
    local q = {}
    for _, method in ipairs({ 'Title', 'Splitter', 'OptionCheckbox', 'OptionSlider', 'Tooltip', 'Text' }) do
        local name = method   -- Lua 5.0: a closure would otherwise see the loop variable's last value
        q[name] = function(self, a, b, c, d, e)
            table.insert(log, { name, a, b, c, d, e })
        end
    end
    return q
end

local function FreshWorld(opts)
    Harness.Reset()
    opts = opts or {}
    _G.KeybindTrainerPath = nil
    _G.KeybindTrainerRebuild = nil
    _G.__active_mods = { { uid = 'keybind-trainer-v1', location = MOD } }

    world = {
        replay = false, selection = {}, prints = {}, notified = {}, logs = {},
        required = {}, postCreate = {}, windows = {}, rebuilds = 0,
        prefs = {},
        keymap = { Q = 'patrol', W = 'builders', M = 'upgrades', Tab = 'pause_unit', Z = 'toggle_repeat_build' },
    }
    SessionIsReplay = function() return false end
    GetFocusArmy = function() return 1 end
    GetSelectedUnits = function() return world.selection end
    print = function(s) table.insert(world.prints, s) end
    LOG = function(s) table.insert(world.logs, 'LOG ' .. tostring(s)) end
    WARN = function(s) table.insert(world.logs, 'WARN ' .. tostring(s)) end

    __blueprints = {
        ueb0101 = { Description = 'Land Factory', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'none' } },
        uel0105 = { Description = 'Engineer', CategoriesHash = { MOBILE = true }, General = { UpgradesFrom = 'none' } },
        ueb1202 = { Description = 'T2 Mex', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'ueb1103', UpgradesFromBase = 'ueb1103' } },
        ueb1103 = { Description = 'T1 Mex', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'none' } },
    }

    local O = Harness.overrides
    O['/lua/keymap/keymapper.lua'] = {
        GetCurrentKeyMap = function() return world.keymap end,
        GetKeyActions = function()
            return {
                builders = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Builders")' },
                upgrades = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Upgrades")' },
                My_Set = { action = 'UI_Lua ReUI.Hotbuild.ProcessHotbuild("My_Set")' },
            }
        end,
        SetUserKeyAction = function() end,
    }
    O['/lua/keymap/unitkeygroups.lua'] = { unitkeygroups = {
        Builders = { 'Land_Factory', 'T1_Engineer', 'T1_Mex' },
        Land_Factory = { 'ueb0101' }, T1_Engineer = { 'uel0105' }, T1_Mex = { 'ueb1103', 'ueb1202' },
        Upgrades = { '_upgrade' },
    } }
    O['/lua/ui/help/tooltips.lua'] = { Tooltips = {} }
    O['/lua/keymap/properkeynames.lua'] = { properKeyNames = {} }
    O['/lua/user/prefs.lua'] = {
        GetFromCurrentProfile = function(k) return world.prefs[k] end,
        SetToCurrentProfile = function(k, v) world.prefs[k] = v end,
    }
    O[MOD .. '/modules/feedback.lua'] = {
        Notify = function(control, key, label) table.insert(world.notified, { key = key, label = label, control = control }) end,
        Destroy = function() end,
    }
    O[MOD .. '/modules/panel.lua'] = {
        Create = function() end, Refresh = function() end, Rebuild = function() end, SetEditing = function() end,
        SetUIHidden = function() end, Destroy = function() end,
    }

    -- ReUI itself
    local modules = {}
    if opts.construction ~= false then
        modules['ReUI.Construction'] = { Status = 'loaded', Path = '/mods/ReUI.Construction/' }
    end
    if opts.hotbuild then
        modules['ReUI.Hotbuild'] = { Status = opts.hotbuildStatus or 'loaded', Path = '/mods/ReUI.Hotbuild/' }
    end
    local Options = {
        Mods = {},
        OptionValue = Reactive,
        Add = function(name, fn) table.insert(world.windows, { name = name, fn = fn }) end,
        Window = function(title, fn) return { title = title, fn = fn } end,
    }
    ReUI = {
        Get = function(name) return modules[name] end,
        Require = function(deps) table.insert(world.required, deps) end,
        Core = { OnPostCreateUI = function(fn) table.insert(world.postCreate, fn) end },
        Options = Options,
    }

    -- ReUI.Construction's modules, as the classes the real panel uses
    world.calls = {}
    local function Component(name)
        return { HandleEvent = function(self, item, event) table.insert(world.calls, name .. ':' .. tostring(event.Type)) end }
    end
    world.engineer = Component('engineer')
    world.factory = Component('factory')
    world.chain = Component('chain')
    world.checkbox = { OnClick = function(self, modifiers) table.insert(world.calls, 'checkbox') end }
    O['/mods/ReUI.Construction/Modules/Components/BuildOptions.lua'] = {
        BuildOptionsHandler = { ComponentClass = world.engineer },
        BuildOptionsFactoryHandler = { ComponentClass = world.factory },
    }
    O['/mods/ReUI.Construction/Modules/Components/UpgradeChain.lua'] = { UpgradeChainHandler = { ComponentClass = world.chain } }
    O['/mods/ReUI.Construction/Modules/Views/ActionCheckBox.lua'] = { ActionCheckBox = world.checkbox }
end

--- Run one of the mod's root files the way ReUI would (own environment, relative import).
local function RunRootFile(file)
    local env = {}
    env.import = function(p)
        if string.sub(p, 1, 1) ~= '/' then p = MOD .. '/' .. p end
        return Harness.import(p)
    end
    Harness.LoadInto(file, env)
    return env
end

local function Item() return { Left = function() return 100 end, Top = function() return 200 end, Width = function() return 40 end, Height = function() return 40 end } end
local function Press(mods, kind) return { Type = kind or 'ButtonPress', Modifiers = mods } end
local function Comp(id) return { data = { id = id }, context = { selection = {} } } end

--------------------------------------------------------------------------------
Say('== options: defaults')
FreshWorld()
local Opts = import(MOD .. '/modules/options.lua')
local cfg = import(MOD .. '/modules/config.lua').Config
local values = Opts.MakeValues(Reactive)
Check('every setting becomes an option', values.orders and values.attackMove and values.buildings and values.upgrades and values.units and values.pause
    and values.repeatBuild and values.toast and values.toastSeconds and values.flash and values.sound and values.panel and values.panelFolded and values.startup)
Check('units default OFF (a ReUI option, off by default)', values.units:Get() == false)
Check('building UPGRADES default OFF, as their own option', values.upgrades:Get() == false)
Check('building CONSTRUCTION and orders default ON', values.buildings:Get() == true and values.orders:Get() == true)
Check('the panel is shown by default and starts unfolded', values.panel:Get() == true and values.panelFolded:Get() == false)
Check('the note length defaults to 1 second', values.toastSeconds:Get() == 1 and cfg.Feedback.ToastSeconds == 1)
Check('plain values when ReUI gives no maker', Opts.MakeValues(nil).units == false and Opts.MakeValues(nil).orders == true)
Check('the trainer ON/OFF switch is NOT a ReUI option', values.enabled == nil)

Say('== options: Bind')
values.buildings:Set(false)           -- what ReUI loaded from the profile
values.units:Set(true)
values.upgrades:Set(true)
Opts.Bind(values)
Check('saved values go into Config when bound', cfg.Lock.Buildings == false and cfg.Lock.Units == true and cfg.Lock.Upgrades == true)
values.upgrades:Set(false)
values.buildings:Set(true)
Check('construction and upgrades are separate settings', cfg.Lock.Upgrades == false and cfg.Lock.Buildings == true)
values.units:Set(false)
Check('later changes go straight into Config', cfg.Lock.Units == false)
values.toastSeconds:Set(99)
Check('a slider value is clamped to its range', cfg.Feedback.ToastSeconds == 6)
values.toastSeconds:Set(0)
Check('...at the bottom too', cfg.Feedback.ToastSeconds == 1)
values.startup:Set(false)
Check('a top-level setting (StartupMessage) works', cfg.StartupMessage == false)
_G.KeybindTrainerRebuild = function() world.rebuilds = world.rebuilds + 1 end
values.panel:Set(false)
Check('hiding the panel rebuilds it (so the arrow goes too)', world.rebuilds == 1 and cfg.Panel.Show == false)
values.panel:Set(false)
Check('...but only when it actually changed', world.rebuilds == 1)
values.panelFolded:Set(true)
Check('"starts folded" is a plain setting', cfg.Panel.StartCollapsed == true and world.rebuilds == 1)
values.flash:Set(false)
Check('other changes do not rebuild anything', world.rebuilds == 1 and cfg.Feedback.Flash == false)
Check('Bind tolerates nonsense', pcall(Opts.Bind, nil) and pcall(Opts.Bind, 5))

Say('== options: the window')
FreshWorld()
Opts = import(MOD .. '/modules/options.lua')
values = Opts.MakeValues(Reactive)
local log = {}
Opts.BuildWindow(FakeQ(log), values)
local kinds = {}
for _, e in ipairs(log) do kinds[e[1]] = (kinds[e[1]] or 0) + 1 end
Check('starts with a heading, not a divider', log[1][1] == 'Title' and log[1][2] == 'What gets locked')
Check('three headings, a divider before the 2nd and 3rd and one before the footnote', kinds.Title == 3 and kinds.Splitter == 3)
Check('one checkbox per toggle (13) and one slider', kinds.OptionCheckbox == 13 and kinds.OptionSlider == 1)
Check('every setting has a tooltip', kinds.Tooltip == 14)
local labels = {}
for _, e in ipairs(log) do if e[1] == 'OptionCheckbox' then labels[e[2]] = true end end
Check('construction and upgrades are separate checkboxes', labels['Building construction'] and labels['Building upgrades'])
Check('the panel can be hidden from the window', labels['Show the panel'])
Check('the window says how to drag the panel', (function() for _, e in ipairs(log) do if e[1] == 'Text' and string.find(e[2], 'drag the panel', 1, true) then return true end end end)())
local unitsAt
for i, e in ipairs(log) do if e[1] == 'OptionCheckbox' and e[2] == 'Units in factories' then unitsAt = i end end
Check('the units checkbox is there, bound to the units option, with its tooltip after it',
    unitsAt and log[unitsAt][3] == values.units and log[unitsAt + 1][1] == 'Tooltip' and string.find(log[unitsAt + 1][3], 'Off by default', 1, true) ~= nil)
Check('the slider gets its range', (function() for _, e in ipairs(log) do if e[1] == 'OptionSlider' then return e[4] == 1 and e[5] == 6 and e[6] == 1 end end end)())

Say('== options: registering the window')
Opts.Register(ReUI.Options, values)
Check('added through Options.Add', table.getn(world.windows) == 1 and world.windows[1].name == 'Keybind Trainer')
local win = world.windows[1].fn({})
Check('...which builds a ReUI window with our title', win.title == 'Keybind Trainer')
local log2 = {}
win.fn(FakeQ(log2))
Check('...whose contents are the settings', table.getn(log2) == table.getn(log))

local editing = {}
_G.KeybindTrainerSetEditing = function(on) table.insert(editing, on) end
local opened = world.windows[1].fn({})
Check('opening the window puts the panel in drag mode', editing[1] == true)
local destroyed = false
opened.OnDestroy(opened)
Check('closing it ends drag mode', editing[2] == false)
local win2 = { OnDestroy = function() destroyed = true end }
Opts.WatchWindow(win2)
win2.OnDestroy(win2)
Check('...and ReUI\'s own OnDestroy still runs', destroyed == true and editing[4] == false)
_G.KeybindTrainerSetEditing = function() error('panel is gone') end
Check('a failing panel never breaks opening or closing the window', pcall(function() local w = world.windows[1].fn({}) w.OnDestroy(w) end))
_G.KeybindTrainerSetEditing = nil
Check('no game running (no hook): opening the window is fine', pcall(function() local w = world.windows[1].fn({}) w.OnDestroy(w) end))

--------------------------------------------------------------------------------
Say('== ReUI entry points')
FreshWorld()
local env = RunRootFile('Options.lua')
Check('Options.lua assigns our option values to ReUI.Options.Mods', ReUI.Options.Mods.KeybindTrainer and ReUI.Options.Mods.KeybindTrainer.units:Get() == false)
env.Main()
Check('Options.lua Main registers the window', table.getn(world.windows) == 1)

FreshWorld()
Harness.overrides['/mods/KeybindTrainer/modules/options.lua'] = nil
env = RunRootFile('Main.lua')
Check('Main.lua declares its version', env.Version == '1.0.0')
Check('...and requires ReUI.Core and ReUI.Options', world.required[1] and world.required[1][1] == 'ReUI.Core >= 1.2.0' and world.required[1][2] == 'ReUI.Options >= 2.0.0')
ReUI.Options.Mods.KeybindTrainer = import(MOD .. '/modules/options.lua').MakeValues(Reactive)
ReUI.Options.Mods.KeybindTrainer.units:Set(true)
env.Main(false)
Check('Main binds the saved options into Config', import(MOD .. '/modules/config.lua').Config.Lock.Units == true)
Check('Main registers one after-UI callback', table.getn(world.postCreate) == 1)
world.postCreate[1](false)
local patched = 0
for _, l in ipairs(world.logs) do if string.find(l, ': locked', 1, true) then patched = patched + 1 end end
Check('the callback patches the four ReUI.Construction parts', patched == 4)

FreshWorld({ construction = false })
env = RunRootFile('Main.lua')
ReUI.Options.Mods.KeybindTrainer = import(MOD .. '/modules/options.lua').MakeValues(Reactive)
env.Main(false)
Check('without ReUI.Construction the callback does nothing, quietly', pcall(world.postCreate[1], false) and table.getn(world.logs) == 0)

--------------------------------------------------------------------------------
Say('== ReUI.Construction: engineer menu')
FreshWorld()
cfg = import(MOD .. '/modules/config.lua').Config
local Reui = import(MOD .. '/modules/reui.lua')
local report = Reui.Install()
Check('Install reports each part as locked', table.getn(report) == 4 and string.find(report[1], 'locked', 1, true) ~= nil)
local item = Item()
world.engineer:HandleEvent(item, Press(LEFT))   -- no data: original must still run (self.data nil)
Check('a component with no blueprint passes through', world.calls[1] == 'engineer:ButtonPress')
world.calls = {}
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(LEFT))
Check('left press on a bound building is refused', table.getn(world.calls) == 0 and world.notified[1].key == 'W' and world.notified[1].label == 'Build Land Factory')
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(RIGHT))
Check('RIGHT press is refused too (ReUI builds on any button here)', table.getn(world.calls) == 0 and table.getn(world.notified) == 2)
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(RIGHT, 'ButtonDClick'))
Check('double clicks are refused', table.getn(world.calls) == 0 and table.getn(world.notified) == 3)
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(LEFT, 'MouseEnter'))
Check('hover events always pass through', world.calls[1] == 'engineer:MouseEnter')
world.calls = {}
world.engineer.HandleEvent(Comp('uel0105'), item, Press(LEFT))
Check('a unit passes by default', world.calls[1] == 'engineer:ButtonPress')
world.calls = {}
world.engineer.HandleEvent(Comp('zzz9999'), item, Press(LEFT))
Check('an unbound building passes', world.calls[1] == 'engineer:ButtonPress')
local wrapped = world.engineer.HandleEvent
Check('Install twice does not wrap twice', Reui.Install() and world.engineer.HandleEvent == wrapped)

Say('== ReUI.Construction: factory menu')
world.calls = {}
world.notified = {}
cfg.Lock.Units = true
world.factory.HandleEvent(Comp('uel0105'), item, Press(LEFT))
Check('with Units on, left press on a unit is refused', table.getn(world.calls) == 0 and world.notified[1].label == 'Build Engineer')
world.factory.HandleEvent(Comp('uel0105'), item, Press(RIGHT))
Check('right press (dequeue) always passes', world.calls[1] == 'factory:ButtonPress')
cfg.Lock.Units = false
world.calls = {}
world.factory.HandleEvent(Comp('uel0105'), item, Press(LEFT))
Check('Units off (the default): clicking units is free', world.calls[1] == 'factory:ButtonPress')
world.calls = {}
world.selection = { { GetBlueprint = function() return { BlueprintId = 'ueb1103', General = { UpgradesTo = 'ueb1202', UpgradesFromBase = 'ueb1103' } } end } }
world.factory.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('a structure upgrade is free by default', world.calls[1] == 'factory:ButtonPress')
world.calls = {}
cfg.Lock.Upgrades = true
world.factory.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('with Upgrades on a structure upgrade is refused and shows the upgrade key', table.getn(world.calls) == 0 and world.notified[table.getn(world.notified)].key == 'M'
    and world.notified[table.getn(world.notified)].label == 'Upgrade to T2 Mex')
cfg.Lock.Upgrades = false

Say('== ReUI.Construction: upgrade chain')
world.calls = {}
world.selection = {}
world.chain.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('building upgrades are NOT locked by default (so the chain works)', world.calls[1] == 'chain:ButtonPress')
world.calls = {}
cfg.Lock.Upgrades = true
world.chain.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('with Upgrades on: always an upgrade, refused with the upgrade key', table.getn(world.calls) == 0 and world.notified[table.getn(world.notified)].key == 'M')
world.chain.HandleEvent(Comp('ueb1202'), item, Press(RIGHT))
Check('any button', table.getn(world.calls) == 0)
cfg.Lock.Buildings = false
world.chain.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('Buildings (construction) is a different switch: off, the upgrade is still refused', table.getn(world.calls) == 0)
cfg.Lock.Upgrades = false
world.chain.HandleEvent(Comp('ueb1202'), item, Press(LEFT))
Check('Upgrades off lets it through', world.calls[1] == 'chain:ButtonPress')
cfg.Lock.Buildings = true

Say('== ReUI.Construction: pause / repeat')
local function Box(which)
    local behaviors = { pause = {}, repeatBuild = {} }
    local panel = { _actionsBehavior = behaviors }
    return { _behavior = behaviors[which], _context = { panel = panel }, IsDisabled = function() return false end }, panel
end
world.calls = {}
local pauseBox = Box('pause')
world.checkbox.OnClick(pauseBox, LEFT)
Check('pause is refused with its key', table.getn(world.calls) == 0 and world.notified[table.getn(world.notified)].key == 'Tab' and world.notified[table.getn(world.notified)].label == 'Pause')
local repeatBox = Box('repeatBuild')
world.checkbox.OnClick(repeatBox, LEFT)
Check('repeat build is refused with its key', table.getn(world.calls) == 0 and world.notified[table.getn(world.notified)].key == 'Z')
world.checkbox.OnClick(pauseBox, RIGHT)
Check('right click passes to ReUI', world.calls[1] == 'checkbox')
world.calls = {}
local strange = Box('pause'); strange._behavior = {}
world.checkbox.OnClick(strange, LEFT)
Check('a checkbox with an unknown behaviour passes', world.calls[1] == 'checkbox')
world.calls = {}
world.checkbox.OnClick({ _behavior = nil }, LEFT)
Check('a checkbox with no behaviour or panel passes', world.calls[1] == 'checkbox')
world.calls = {}
cfg.Lock.Pause = false
world.checkbox.OnClick(pauseBox, LEFT)
Check('Lock.Pause = false is honoured', world.calls[1] == 'checkbox')
cfg.Lock.Pause = true

Say('== ReUI.Construction: fail open, replays, off')
world.calls = {}
SessionIsReplay = function() error('boom') end
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(LEFT))
Check('an error in the check lets ReUI have the click', world.calls[1] == 'engineer:ButtonPress')
SessionIsReplay = function() return true end
world.calls = {}
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(LEFT))
Check('nothing is refused in a replay', world.calls[1] == 'engineer:ButtonPress')
SessionIsReplay = function() return false end
import(MOD .. '/modules/trainer.lua').SetEnabled(false)
world.calls = {}
world.engineer.HandleEvent(Comp('ueb0101'), item, Press(LEFT))
Check('nothing is refused while switched off', world.calls[1] == 'engineer:ButtonPress')

Say('== ReUI classes that are not what we expect')
FreshWorld()
Harness.overrides['/mods/ReUI.Construction/Modules/Components/BuildOptions.lua'] = { BuildOptionsHandler = {}, BuildOptionsFactoryHandler = { ComponentClass = world.factory } }
Harness.overrides['/mods/ReUI.Construction/Modules/Views/ActionCheckBox.lua'] = { ActionCheckBox = { } }
Harness.overrides['/lua/maui/checkbox.lua'] = { Checkbox = { OnClick = function() end } }
report = import(MOD .. '/modules/reui.lua').Install()
Check('a missing class is reported and the rest still patched', string.find(report[1], 'NOT patched', 1, true) ~= nil and string.find(report[2], 'locked', 1, true) ~= nil)
Check('a checkbox class without its own OnClick falls back to the base Checkbox', string.find(report[4], 'locked', 1, true) ~= nil)

--------------------------------------------------------------------------------
Say('== ReUI.Hotbuild keys')
FreshWorld({ hotbuild = true })
local K = import(MOD .. '/modules/keybinds.lua')
Check('names are formatted the way ReUI.Actions formats them', K.FormatHotbuildName('My Set!') == 'My_Set_' and K.FormatHotbuildName('abc') == 'abc' and K.FormatHotbuildName('a  b--c') == 'a_b_c')
local ids = K.CollectHotbuildIds({
    Construction = { { aeon = 'UAB0101', uef = 'ueb0101' }, { uef = { templateData = {} } } },
    Land = { uef = 'uel0105' }, Air = { 'not-a-unit-table-entry' }, Naval = 'junk',
})
Check('a saved set flattens to its blueprint ids, lower case, templates skipped', ids.uab0101 and ids.ueb0101 and ids.uel0105 and ids['not-a-unit-table-entry'] and not ids.naval)
world.prefs.hotbuildoverhaul = { ['My Set'] = { Construction = { { uef = 'ueb0101' } }, Land = { uef = 'uel0105' } } }
world.keymap = { ['Ctrl-B'] = 'My_Set', W = 'builders' }
K.Invalidate()
Check('a key on a ReUI.Hotbuild set locks its units (the narrowest set wins)', K.GetBuildKey('uel0105') == 'Ctrl-B' and K.GetBuildKey('ueb0101') == 'Ctrl-B')
Check('FAF\'s own groups still work alongside', K.GetBuildKey('ueb1103') == 'W')

FreshWorld({ hotbuild = true, hotbuildStatus = 'failed' })
world.prefs.hotbuildoverhaul = { ['My Set'] = { Land = { uef = 'uel0105' } } }
world.keymap = { ['Ctrl-B'] = 'My_Set', W = 'builders' }
K = import(MOD .. '/modules/keybinds.lua')
Check('...but not when ReUI.Hotbuild is not loaded (a leftover key does nothing)', K.GetBuildKey('uel0105') == 'W')

FreshWorld()
world.prefs.hotbuildoverhaul = { ['My Set'] = { Land = { uef = 'uel0105' } } }
world.keymap = { ['Ctrl-B'] = 'My_Set', W = 'builders' }
_G.ReUI = nil
K = import(MOD .. '/modules/keybinds.lua')
Check('...and nothing changes without ReUI at all', K.GetBuildKey('uel0105') == 'W')

Say(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
