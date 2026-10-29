--******************************************************************************
--** Keybind Trainer -- modules/config.lua
--**
--** Every tunable in one place. Edit and restart the game.
--**
--** With ReUI installed, the same settings appear in its options window (see
--** Options.lua / modules/options.lua) and what you pick there wins over the
--** values below. Without ReUI, the values below are what is used.
--**
--** (The ON/OFF state is NOT here: it is remembered per profile, and flipped by
--** the panel at the top of the screen or the optional toggle keybind.)
--******************************************************************************

Config = {
    -- Whether the trainer starts ON the very first time (before a choice is saved).
    EnabledByDefault = true,

    -- What gets locked. A button is only ever locked if its action actually has
    -- a key bound to it right now, so unbound buttons always stay clickable.
    Lock = {
        Orders      = true,  -- move / attack / patrol / reclaim / stop / toggles ...
        AttackMove  = true,  -- the Attack Move button (its shortcut is Alt + Right Click)
        Buildings   = true,  -- constructing buildings: structure icons in the build menu
        Upgrades    = false, -- upgrading buildings (off: clicking an upgrade stays free)
        Units       = false, -- unit icons in factory / gateway menus (off: clicking units stays free)
        Pause       = true,  -- the pause button of the construction panel
        RepeatBuild = true,  -- the infinite / repeat-build button of the construction panel
    },

    Feedback = {
        Toast        = true,  -- floating "[Q] Patrol" note above the button you clicked
        ToastSeconds = 1,     -- whole seconds (ReUI's slider steps by 1)
        Flash        = true,  -- brief red flash on the button
        Sound        = true,  -- the game's standard "not allowed" blip
    },

    -- The small panel with the ON / OFF label. It sits to the LEFT of the game's menu
    -- strip at the top of the screen, has FAF's collapse arrow, and can be dragged
    -- along the left / right / top edge while ReUI's options window is open.
    Panel = {
        Show           = true,   -- false: no panel and no collapse arrow at all
        StartCollapsed = false,  -- fold it to just its arrow at the start of a game
        Gap            = 6,      -- pixels between the panel and the menu strip
    },

    -- Add a "Toggle Keybind Trainer" action to the keybinding window (F1, category
    -- "Mods"). It has no key by default; bind one if you want a keyboard on/off.
    RegisterKeyAction = true,

    -- One line of chat-style text when a game starts with the trainer on.
    StartupMessage = true,
}
