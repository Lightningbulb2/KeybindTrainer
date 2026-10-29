--******************************************************************************
--** Keybind Trainer -- hook/lua/ui/game/gamemain.lua
--**
--** Starts the trainer once the whole game UI exists (the panel needs the
--** root frame) and tears it down with the UI.
--******************************************************************************

local KbtOriginalCreateUI = CreateUI
function CreateUI(isReplay)
    KbtOriginalCreateUI(isReplay)

    local ok, err = pcall(function()
        local path = '/mods/KeybindTrainer'
        if __active_mods then
            for _, mod in ipairs(__active_mods) do
                if mod.uid == 'keybind-trainer-v1' and mod.location then
                    path = mod.location
                    break
                end
            end
        end
        rawset(_G, 'KeybindTrainerPath', path)

        local Trainer = import(path .. '/modules/trainer.lua')
        Trainer.Init(isReplay)

        AddOnUIDestroyedFunction(function()
            pcall(Trainer.Destroy)
        end)
    end)

    if not ok then
        LOG('KeybindTrainer: startup failed, the trainer is disabled for this session: ' .. tostring(err))
    end
end

--- Screen capture mode: the game hides / shows its interface here. The panel is
--- not part of what the game hides, so tell it.
local KbtOriginalHideGameUI = HideGameUI
function HideGameUI(state)
    KbtOriginalHideGameUI(state)
    pcall(function()
        local path = rawget(_G, 'KeybindTrainerPath')
        if path then
            import(path .. '/modules/trainer.lua').OnUIHiddenChanged()
        end
    end)
end
