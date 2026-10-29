-- Loads ReUI.Construction's REAL source files (the build menu components and the
-- action checkbox) behind a permissive stand-in for ReUI's framework, applies the
-- mod's patch to the REAL classes, and clicks them.
--
-- What this proves: the names and signatures modules/reui.lua depends on exist in
-- ReUI's actual code (BuildOptionsHandler.ComponentClass, HandleEvent(self, item,
-- event), self.data.id, ActionCheckBox, the panel's _actionsBehavior ...), and
-- that a refused click never reaches ReUI's own handler while an allowed one does.
-- What it cannot prove: how the framework stand-in differs from the real one.
--
--     lua50 extras/test_reui_real.lua <path to a checkout of 4z0t/FAF-UI-Mods>

local repo = arg[1]
assert(repo, 'pass the path of a 4z0t/FAF-UI-Mods checkout')
dofile('extras/harness.lua')
Harness.Mount('/mods/KeybindTrainer', '.')
Harness.Mount('/mods/ReUI.Construction', repo .. '/mods/ReUI.Construction')
local MOD = '/mods/KeybindTrainer'

local Say = print
local passed, failed = 0, 0
local function Check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1 Say('  FAIL  ' .. name) end
end

--------------------------------------------------------------------------------
-- a framework stand-in: anything you touch is "something", except the few things
-- the class definitions need to be real
--------------------------------------------------------------------------------
local Any
Any = setmetatable({}, {
    __index = function(t, k) return Any end,
    __call = function() return Any end,
    __add = function() return Any end, __sub = function() return Any end,
    __mul = function() return Any end, __div = function() return Any end,
    __concat = function() return Any end, __unm = function() return Any end,
})

--- ReUI.Core.Class: flat class tables, like FAF's own (derived classes carry copies
--- of the base's fields; instances use the class as their metatable).
local function Class(...)
    local bases = arg
    return function(spec)
        local c = {}
        for i = 1, bases.n do
            if type(bases[i]) == 'table' then
                for k, v in pairs(bases[i]) do c[k] = v end
            end
        end
        for k, v in pairs(spec or {}) do c[k] = v end
        c.__index = c
        return c
    end
end

local world = { calls = {}, notified = {}, prefs = {}, selection = {}, issued = {} }

local function Setup()
    Harness.Reset()
    _G.KeybindTrainerPath = nil
    _G.__active_mods = { { uid = 'keybind-trainer-v1', location = MOD } }
    world.calls, world.notified, world.issued, world.selection = {}, {}, {}, {}

    ReUI = setmetatable({
        Core = setmetatable({ Class = Class, Property = function(t) return t end }, { __index = function() return Any end }),
        Get = function(name)
            if name == 'ReUI.Construction' then return { Status = 'loaded', Path = '/mods/ReUI.Construction/' } end
        end,
    }, { __index = function() return Any end })

    categories = Any
    EntityCategoryContains = function() return false end
    table.empty = function(t) return next(t) == nil end
    table.deepcopy = function(t) return t end
    PlaySound = function() end
    Sound = function(t) return t end
    ClearBuildTemplates = function() end
    SelectUnits = function(sel) table.insert(world.calls, 'SelectUnits') end
    IssueBlueprintCommand = function(...) table.insert(world.issued, arg[2]) end
    GetSelectedUnits = function() return world.selection end
    SessionIsReplay = function() return false end
    GetFocusArmy = function() return 1 end
    print = function() end

    __blueprints = {
        ueb0101 = { Description = 'Land Factory', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'none' } },
        uel0105 = { Description = 'Engineer', CategoriesHash = { MOBILE = true }, General = { UpgradesFrom = 'none' } },
        ueb1103 = { Description = 'T1 Mex', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'none' } },
        ueb1202 = { Description = 'T2 Mex', CategoriesHash = { STRUCTURE = true }, General = { UpgradesFrom = 'ueb1103', UpgradesFromBase = 'ueb1103' } },
    }

    local O = Harness.overrides
    O['/lua/ui/game/commandmode.lua'] = { StartCommandMode = function(kind, data) table.insert(world.calls, 'StartCommandMode:' .. tostring(data and data.name)) end }
    O['/lua/keymap/keymapper.lua'] = {
        GetCurrentKeyMap = function() return { W = 'builders', M = 'upgrades', Tab = 'pause_unit', Z = 'toggle_repeat_build' } end,
        GetKeyActions = function() return {
            builders = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Builders")' },
            upgrades = { action = 'UI_Lua import("/lua/keymap/hotbuild.lua").buildAction("Upgrades")' },
        } end,
        SetUserKeyAction = function() end,
    }
    O['/lua/keymap/unitkeygroups.lua'] = { unitkeygroups = { Builders = { 'ueb0101', 'uel0105' }, Upgrades = { '_upgrade' } } }
    O['/lua/maui/checkbox.lua'] = { Checkbox = { OnClick = function(self, modifiers) table.insert(world.calls, 'baseCheckboxOnClick') end } }
    O['/lua/ui/help/tooltips.lua'] = { Tooltips = {} }
    O['/lua/keymap/properkeynames.lua'] = { properKeyNames = {} }
    O['/lua/user/prefs.lua'] = { GetFromCurrentProfile = function(k) return world.prefs[k] end, SetToCurrentProfile = function(k, v) world.prefs[k] = v end }
    O[MOD .. '/modules/feedback.lua'] = {
        Notify = function(control, key, label) table.insert(world.notified, { key = key, label = label }) end,
        Destroy = function() end,
    }
    O[MOD .. '/modules/panel.lua'] = {
        Create = function() end, Refresh = function() end, Rebuild = function() end, SetEditing = function() end,
        SetUIHidden = function() end, Destroy = function() end,
    }

    -- anything ReUI's files import from the game that we have not mounted is "something"
    for _, file in ipairs({ 'Modules/Components/BuildOptions.lua', 'Modules/Components/UpgradeChain.lua', 'Modules/Views/ActionCheckBox.lua',
                            'Modules/Components/ConstructionItemComponent.lua' }) do
        local src = Harness.ReadFile(repo .. '/mods/ReUI.Construction/' .. file)
        for path in string.gfind(src, 'import%s*%(%s*["\'](/[^"\']+)["\']%s*%)') do
            if not Harness.files[string.lower(path)] then
                if not Harness.overrides[path] then Harness.overrides[path] = Any end
            end
        end
    end
end

local function Item() return { Left = function() return 0 end, Top = function() return 0 end, Width = function() return 1 end, Height = function() return 1 end, UpdatePanel = function() table.insert(world.calls, 'UpdatePanel') end } end
local function Event(kind, mods) return { Type = kind, Modifiers = mods } end
local function Instance(class, id)
    local inst = setmetatable({ data = { id = id, type = 'item' }, context = { selection = world.selection } }, class)
    -- the engineer / factory items call these on themselves; observe instead of building
    inst.OrderConstruction = function(self, sel, bp, count) table.insert(world.calls, 'OrderConstruction:' .. bp) end
    inst.RemoveFromQueue = function(self, unit, bp, count) table.insert(world.calls, 'RemoveFromQueue:' .. bp) end
    inst.InsertFrontQueue = function() table.insert(world.calls, 'InsertFrontQueue') end
    return inst
end
local function Has(prefix)
    for _, c in ipairs(world.calls) do if string.find(c, prefix, 1, true) == 1 then return true end end
    return false
end

--------------------------------------------------------------------------------
Say('== load ReUI.Construction\'s real files')
Setup()
local BuildOptions = import('/mods/ReUI.Construction/Modules/Components/BuildOptions.lua')
local UpgradeChain = import('/mods/ReUI.Construction/Modules/Components/UpgradeChain.lua')
local ActionBox = import('/mods/ReUI.Construction/Modules/Views/ActionCheckBox.lua')

Check('BuildOptions.lua defines BuildOptionsHandler.ComponentClass.HandleEvent', type(BuildOptions.BuildOptionsHandler) == 'table'
    and type(BuildOptions.BuildOptionsHandler.ComponentClass) == 'table' and type(BuildOptions.BuildOptionsHandler.ComponentClass.HandleEvent) == 'function')
Check('...and BuildOptionsFactoryHandler.ComponentClass.HandleEvent', type(BuildOptions.BuildOptionsFactoryHandler) == 'table'
    and type(BuildOptions.BuildOptionsFactoryHandler.ComponentClass.HandleEvent) == 'function')
Check('UpgradeChain.lua defines UpgradeChainHandler.ComponentClass.HandleEvent', type(UpgradeChain.UpgradeChainHandler) == 'table'
    and type(UpgradeChain.UpgradeChainHandler.ComponentClass.HandleEvent) == 'function')
Check('ActionCheckBox.lua defines the ActionCheckBox class', type(ActionBox.ActionCheckBox) == 'table')

local engineerClass = BuildOptions.BuildOptionsHandler.ComponentClass
local factoryClass = BuildOptions.BuildOptionsFactoryHandler.ComponentClass
local chainClass = UpgradeChain.UpgradeChainHandler.ComponentClass
local checkboxClass = ActionBox.ActionCheckBox

Say('== before the patch: the real handlers run')
local item = Item()
engineerClass.HandleEvent(Instance(engineerClass, 'ueb0101'), item, Event('ButtonPress', { Left = true }))
Check('real engineer item starts the build', Has('StartCommandMode:'))
world.calls = {}
factoryClass.HandleEvent(Instance(factoryClass, 'uel0105'), item, Event('ButtonPress', { Left = true }))
Check('real factory item orders construction', Has('OrderConstruction:uel0105'))
world.calls = {}
chainClass.HandleEvent(Instance(chainClass, 'ueb1202'), item, Event('ButtonPress', { Left = true }))
Check('real upgrade chain item runs its upgrade path', Has('SelectUnits'))
world.calls = {}

Say('== install the patch on the real classes')
local report = import(MOD .. '/modules/reui.lua').Install()
local lockedCount = 0
for _, line in ipairs(report) do if string.find(line, ': locked', 1, true) then lockedCount = lockedCount + 1 else Say('  report: ' .. line) end end
Check('all four parts report locked', lockedCount == 4)

Say('== real engineer item')
engineerClass.HandleEvent(Instance(engineerClass, 'ueb0101'), item, Event('ButtonPress', { Left = true }))
Check('bound building: refused, ReUI never starts the build', not Has('StartCommandMode:') and world.notified[1] and world.notified[1].key == 'W')
engineerClass.HandleEvent(Instance(engineerClass, 'ueb0101'), item, Event('ButtonPress', { Right = true }))
Check('...right button too', not Has('StartCommandMode:') and table.getn(world.notified) == 2)
engineerClass.HandleEvent(Instance(engineerClass, 'zzz9999'), item, Event('ButtonPress', { Left = true }))
Check('an unbound building still builds', Has('StartCommandMode:'))
world.calls = {}

Say('== real factory item')
factoryClass.HandleEvent(Instance(factoryClass, 'uel0105'), item, Event('ButtonPress', { Left = true }))
Check('a unit: still orders construction (units are not locked by default)', Has('OrderConstruction:uel0105') and Has('UpdatePanel'))
world.calls = {}
import(MOD .. '/modules/config.lua').Config.Lock.Units = true
factoryClass.HandleEvent(Instance(factoryClass, 'uel0105'), item, Event('ButtonPress', { Left = true }))
Check('...refused once Lock.Units is on', not Has('OrderConstruction') and not Has('UpdatePanel'))
world.selection = { {} }
factoryClass.HandleEvent(Instance(factoryClass, 'uel0105'), item, Event('ButtonPress', { Right = true }))
Check('right button still dequeues', Has('RemoveFromQueue:uel0105'))
import(MOD .. '/modules/config.lua').Config.Lock.Units = false
world.selection = { {} }
world.calls = {}
local refusals = table.getn(world.notified)
local shown = false
Harness.overrides['/lua/ui/game/unitviewdetail.lua'] = nil
local ok = pcall(factoryClass.HandleEvent, Instance(factoryClass, 'ueb0101'), item, Event('MouseEnter', {}))
Check('hover on a bound building reaches ReUI untouched: no error and no refusal', ok and table.getn(world.notified) == refusals)
world.selection = {}

Say('== real upgrade chain item')
world.calls = {}
world.notified = {}
world.selection = { { GetUnitId = function() return 'ueb1103' end, GetBlueprint = function() return { BlueprintId = 'ueb1103', General = { UpgradesTo = 'ueb1202' } } end } }
chainClass.HandleEvent(Instance(chainClass, 'ueb1202'), item, Event('ButtonPress', { Left = true }))
Check('building upgrades are free by default: the REAL upgrade code issues the upgrade', world.issued[1] == 'ueb1202' and Has('SelectUnits') and table.getn(world.notified) == 0)
world.calls, world.issued = {}, {}
import(MOD .. '/modules/config.lua').Config.Lock.Upgrades = true
chainClass.HandleEvent(Instance(chainClass, 'ueb1202'), item, Event('ButtonPress', { Left = true }))
Check('with Upgrades on: refused, ReUI issues no upgrade order', table.getn(world.issued) == 0 and not Has('SelectUnits') and world.notified[1].key == 'M' and world.notified[1].label == 'Upgrade to T2 Mex')
import(MOD .. '/modules/config.lua').Config.Lock.Buildings = false
world.notified = {}
chainClass.HandleEvent(Instance(chainClass, 'ueb1202'), item, Event('ButtonPress', { Left = true }))
Check('construction is a separate switch: Buildings off, the upgrade is still refused', table.getn(world.issued) == 0 and world.notified[1] ~= nil)
import(MOD .. '/modules/config.lua').Config.Lock.Buildings = true
import(MOD .. '/modules/config.lua').Config.Lock.Upgrades = false

Say('== real pause / repeat checkbox')
world.calls = {}
world.notified = {}
Check('the real class has an OnClick for the patch to wrap (flattened from Checkbox in the game; here via the fallback)', type(checkboxClass.OnClick) == 'function' and checkboxClass.KbtWrapped == true)
local behaviors = { pause = {}, repeatBuild = {} }
local box = setmetatable({ _behavior = behaviors.pause, _context = { panel = { _actionsBehavior = behaviors } }, IsDisabled = function() return false end }, checkboxClass)
checkboxClass.OnClick(box, { Left = true })
Check('pause refused with its key', world.notified[1] and world.notified[1].key == 'Tab')
box._behavior = behaviors.repeatBuild
checkboxClass.OnClick(box, { Left = true })
Check('repeat build refused with its key', world.notified[2] and world.notified[2].key == 'Z')

Say(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
