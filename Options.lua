--******************************************************************************
--** Keybind Trainer -- Options.lua (ReUI's options window)
--**
--** The settings, their tooltips and defaults come from modules/options.lua,
--** which takes the defaults from config.lua. ReUI turns the values assigned
--** here into saved options, and calls Main when its options window is opened.
--******************************************************************************

local KeybindTrainerOptions = import('modules/options.lua')

-- ReUI turns these into saved options (ReactiveOption) when they are assigned here.
ReUI.Options.Mods[KeybindTrainerOptions.MOD_KEY] = KeybindTrainerOptions.MakeValues(ReUI.Options.OptionValue)

function Main()
    KeybindTrainerOptions.Register(ReUI.Options, ReUI.Options.Mods[KeybindTrainerOptions.MOD_KEY])
end
