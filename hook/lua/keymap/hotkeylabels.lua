--******************************************************************************
--** Keybind Trainer -- hook/lua/keymap/hotkeylabels.lua
--**
--** init() is called when a game starts and again every time the player confirms
--** a new keymap in the keybinding window. That is exactly when our cached
--** "which button has which key" tables go stale, so drop them here. They are
--** rebuilt lazily on the next click.
--**
--** Nothing is imported at file scope: hotkeylabels.lua itself imports
--** construction.lua and orders.lua, which we also hook.
--******************************************************************************

local KbtOriginalInit = init
function init()
    KbtOriginalInit()

    pcall(function()
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
        import(path .. '/modules/keybinds.lua').Invalidate()
    end)
end
