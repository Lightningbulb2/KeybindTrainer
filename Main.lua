--******************************************************************************
--** Keybind Trainer -- Main.lua (ReUI entry point)
--**
--** Loaded by ReUI only (see `ReUI` in mod_info.lua); without ReUI this file is
--** never run and the mod uses config.lua as it is. Does two things:
--**   * passes ReUI's saved settings, and every later change, into Config
--**     (modules/options.lua);
--**   * once every ReUI module has loaded, locks ReUI.Construction's panel too,
--**     if it is installed (modules/reui.lua). Not required: when it is not
--**     there, nothing happens and the base game's panels are used.
--******************************************************************************

Version = '1.0.0'

ReUI.Require
{
    'ReUI.Core >= 1.2.0',
    'ReUI.Options >= 2.0.0',
}

function Main(isReplay)
    local Options = import('modules/options.lua')
    Options.Bind(ReUI.Options.Mods[Options.MOD_KEY])

    -- After the interface exists, so ReUI.Construction (loaded in any order
    -- relative to us) has certainly run its Main and defined its classes.
    ReUI.Core.OnPostCreateUI(function(isReplayUI)
        local ok, result = pcall(function()
            return import('modules/reui.lua').Install()
        end)
        if not ok then
            WARN('KeybindTrainer: ReUI panel support failed: ' .. tostring(result))
            return
        end
        for _, line in ipairs(result) do
            LOG('KeybindTrainer: ' .. line)
        end
    end)
end
