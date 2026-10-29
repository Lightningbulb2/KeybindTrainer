--******************************************************************************
--** Keybind Trainer -- modules/reui.lua
--**
--** Makes the lock work in ReUI's replacement panels.
--**
--** The orders panel needs nothing: no ReUI mod replaces it, so orders.lua's
--** buttons (hooked in hook/lua/ui/game/orders.lua) are the same with or without
--** ReUI.
--**
--** The build menu does. ReUI.Construction replaces construction.lua's panel and
--** stubs out its OnClickHandler / CreateExtraControls, so the base game hooks
--** never fire there. Its icons are grid items whose clicks reach a component
--** class's HandleEvent(self, item, event) (the blueprint id is self.data.id),
--** and pause / repeat-build are ActionCheckBox controls. Hotkeys never go
--** through any of these (hotbuild issues commands itself; ReUI.Construction
--** replaces ToggleUnitPause), so, as in the base game, refusing a click can
--** never block a keybind.
--**
--** What is patched (Install, once per game, after every ReUI module has loaded):
--**   BuildOptionsHandler.ComponentClass         engineer / commander menu
--**       ANY button starts a build there (ReUI does not look at the button),
--**       so any button is refused.
--**   BuildOptionsFactoryHandler.ComponentClass  factory / gateway menu, also its
--**       structure upgrades. Left = order, right = dequeue: only left is refused.
--**   UpgradeChainHandler.ComponentClass         the upgrade chain of a structure.
--**       Any button upgrades: any button is refused, always as an upgrade.
--**   ActionCheckBox.OnClick                     pause and repeat-build.
--**
--** FAF class tables are flat tables that every instance looks its methods up in,
--** so replacing a method on the class takes effect for instances that already
--** exist. Everything is pcall'd: if ReUI changes shape, that button simply stays
--** unlocked (and Install says which part it could not patch).
--******************************************************************************

--- The ReUI module's folder ('/mods/ReUI.Construction/'), if it is loaded.
---@param name string
---@return string | nil
local function ModulePath(name)
    local reui = rawget(_G, 'ReUI')
    if not reui then
        return nil
    end
    local ok, module = pcall(function() return reui.Get(name) end)
    if ok and module and module.Status == 'loaded' and module.Path then
        return module.Path
    end
    return nil
end

--- Is `name` a ReUI module that is loaded this game?
function IsLoaded(name)
    return ModulePath(name) ~= nil
end

local function Trainer()
    return import('trainer.lua')
end

--- A click on a grid item: ask the trainer about the blueprint it stands for.
local function CheckItem(component, item, event, opts)
    local data = component.data
    local id = data and data.id
    if not id then
        return false
    end
    return Trainer().CheckBuildItem(item, id, event.Modifiers, opts)
end

--- Wrap a component class's HandleEvent so a refused press never reaches ReUI.
---@param class table
---@param opts table|nil   passed on to the trainer (anyButton, upgrade)
---@return boolean         # whether it is (now) wrapped
function WrapItemClass(class, opts)
    if type(class) ~= 'table' or type(class.HandleEvent) ~= 'function' then
        return false
    end
    if rawget(class, 'KbtWrapped') then
        return true
    end

    local original = class.HandleEvent
    class.HandleEvent = function(self, item, event)
        if event and (event.Type == 'ButtonPress' or event.Type == 'ButtonDClick') then
            local ok, refused = pcall(CheckItem, self, item, event, opts)
            if ok and refused then
                return
            end
        end
        return original(self, item, event)
    end
    class.KbtWrapped = true
    return true
end

--- Which of the panel's two action buttons is this? 'pause', 'repeat_build', or nil.
--- Each button holds one behaviour instance; the panel keeps the pair by name.
function WhichAction(box)
    local behavior = box._behavior
    local context = box._context
    local panel = context and context.panel
    local map = panel and panel._actionsBehavior
    if not behavior or not map then
        return nil
    end
    if behavior == map.pause then
        return 'pause'
    elseif behavior == map.repeatBuild then
        return 'repeat_build'
    end
    return nil
end

local function CheckAction(box, modifiers)
    local which = WhichAction(box)
    if not which then
        return false
    end
    return Trainer().CheckPanel(box, modifiers, which)
end

--- Wrap the action checkbox's OnClick (a mouse click: the key path never calls it).
---@param class table
---@return boolean
function WrapActionCheckBox(class)
    if type(class) ~= 'table' then
        return false
    end
    if rawget(class, 'KbtWrapped') then
        return true
    end

    -- The class normally carries OnClick flattened in from maui's Checkbox; if it
    -- ever does not, the base one is exactly what would have run.
    local original = class.OnClick
    if type(original) ~= 'function' then
        original = import('/lua/maui/checkbox.lua').Checkbox.OnClick
    end
    if type(original) ~= 'function' then
        return false
    end
    class.OnClick = function(self, modifiers)
        local ok, refused = pcall(CheckAction, self, modifiers)
        if ok and refused then
            return
        end
        return original(self, modifiers)
    end
    class.KbtWrapped = true
    return true
end

--- Patch ReUI.Construction if it is loaded. Returns a list of what was patched
--- and what could not be, for the log.
---@return string[]
function Install()
    local report = {}
    local base = ModulePath('ReUI.Construction')
    if not base then
        return report
    end

    local function Try(what, fn)
        local ok, result = pcall(fn)
        if ok and result then
            table.insert(report, what .. ': locked')
        else
            table.insert(report, what .. ': NOT patched' .. (ok and '' or (' (' .. tostring(result) .. ')')))
        end
    end

    Try('ReUI.Construction engineer menu', function()
        local module = import(base .. 'Modules/Components/BuildOptions.lua')
        return WrapItemClass(module.BuildOptionsHandler.ComponentClass, { anyButton = true })
    end)
    Try('ReUI.Construction factory menu', function()
        local module = import(base .. 'Modules/Components/BuildOptions.lua')
        return WrapItemClass(module.BuildOptionsFactoryHandler.ComponentClass, nil)
    end)
    Try('ReUI.Construction upgrade chain', function()
        local module = import(base .. 'Modules/Components/UpgradeChain.lua')
        return WrapItemClass(module.UpgradeChainHandler.ComponentClass, { anyButton = true, upgrade = true })
    end)
    Try('ReUI.Construction pause / repeat buttons', function()
        local module = import(base .. 'Modules/Views/ActionCheckBox.lua')
        return WrapActionCheckBox(module.ActionCheckBox)
    end)

    return report
end
