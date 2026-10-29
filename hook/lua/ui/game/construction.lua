--******************************************************************************
--** Keybind Trainer -- hook/lua/ui/game/construction.lua
--**
--** 1) The build menu: every icon's OnClick is the module-level OnClickHandler,
--**    so wrapping that one global covers every unit and structure button.
--**    Hotkeys never come through here (hotbuild issues blueprint commands
--**    itself); the only non-mouse caller is BuildTemplate, which passes no
--**    modifiers and is therefore always allowed.
--** 2) The pause and repeat-build buttons of the panel.
--**
--** Only module globals are used (OnClickHandler, CreateExtraControls, controls),
--** never this file's locals. Every path is pcall'd and falls back to the
--** original behaviour.
--******************************************************************************

local function KbtTrainer()
    local path = rawget(_G, 'KeybindTrainerPath')
    if not path then
        path = '/mods/KeybindTrainer'
        if __active_mods then
            for _, mod in ipairs(__active_mods) do
                if mod.uid == 'keybind-trainer-v1' and mod.location then
                    path = mod.location
                    break
                end
            end
        end
        rawset(_G, 'KeybindTrainerPath', path)
    end
    return import(path .. '/modules/trainer.lua')
end

local function KbtCheckBuild(button, modifiers)
    return KbtTrainer().CheckBuild(button, modifiers)
end

local KbtOriginalOnClickHandler = OnClickHandler
function OnClickHandler(button, modifiers)
    local ok, blocked = pcall(KbtCheckBuild, button, modifiers)
    if ok and blocked then
        return
    end
    return KbtOriginalOnClickHandler(button, modifiers)
end

--- Wrap a panel button's OnClick once. `which` is 'pause' or 'repeat_build'.
local function KbtWrapPanelButton(btn, which)
    if not btn then
        return
    end
    -- The original re-assigns extraBtn1.OnClick every time, but leaves
    -- extraBtn2.OnClick alone: never wrap our own wrapper.
    if btn.KbtWrapper and btn.OnClick == btn.KbtWrapper then
        return
    end
    local original = btn.OnClick
    local wrapper = function(self, modifiers)
        local ok, blocked = pcall(function()
            return KbtTrainer().CheckPanel(self, modifiers, which)
        end)
        if ok and blocked then
            return
        end
        return original(self, modifiers)
    end
    btn.OnClick = wrapper
    btn.KbtWrapper = wrapper
end

local function KbtWrapExtraControls(controlType)
    -- extraBtn1 is only the repeat-build button in these two tabs; elsewhere it
    -- is "save template", which has no keybind.
    if controlType == 'construction' or controlType == 'templates' then
        KbtWrapPanelButton(controls.extraBtn1, 'repeat_build')
    end
    KbtWrapPanelButton(controls.extraBtn2, 'pause')
end

local KbtOriginalCreateExtraControls = CreateExtraControls
function CreateExtraControls(controlType)
    KbtOriginalCreateExtraControls(controlType)
    local ok, err = pcall(KbtWrapExtraControls, controlType)
    if not ok then
        LOG('KeybindTrainer: could not wrap the panel buttons: ' .. tostring(err))
    end
end
