name = "Keybind Trainer"
uid = "keybind-trainer-v1"
description =
"Learn your keybinds by being unable to avoid them. Clicking a UI button that has a keybind will block it and tell you to use the keybind. Github at: https://github.com/Lightningbulb2/KeybindTrainer"
copyright = "Licensed under the FAF Vault License. Free to use and modify."
author = "Lightningbulb"
url = "https://github.com/Lightningbulb2/KeybindTrainer"
icon = "/mods/KeybindTrainer/icon.png"
version = 1
exclusive = false
enabled = true
ui_only = true
selectable = true
conflicts = {}

-- Optional: with ReUI installed, the settings show in its options window and the
-- lock also covers ReUI.Construction's panel (Main.lua, Options.lua,
-- modules/options.lua, modules/reui.lua). Not required. ReUI finds the mod by
-- this name, so the folder must be called exactly KeybindTrainer.
ReUI = "KeybindTrainer=1.0.0"

-- Same load-order workaround as the other UI mods in this family: load before
-- Supreme Scoreboard so it cannot break UI loading in co-op missions.
before = { "CHEESEBERRY-a1e2-c4t4-scfa-ssbmod-v0200" }

--[[

### Changelog

V1

Feature: order buttons (move, attack, patrol, reclaim, stop, toggles, ...) cannot be clicked while their action has a key bound

Feature: building icons in the build menu cannot be clicked while a hotbuild key covers them. Building UPGRADES and unit icons in factories are separate switches and are NOT locked by default (ReUI options, or Config.Lock.Upgrades / Config.Lock.Units)

Feature: pause and repeat-build buttons are locked the same way

Feature: a note above the clicked button shows the key to press instead, plus a red flash and the standard error sound

Feature: a small panel to the left of the game's menu strip (ON/OFF, number of refused clicks; click to switch), remembered per profile. It has FAF's collapse arrow, can be dragged along the left/right/top screen edge while ReUI's options window is open (with a Reset position button), hides in screen capture mode, and can be hidden altogether, arrow included, from the ReUI options

Feature: ReUI support: all settings in ReUI's options window (with tooltips); also locks ReUI.Construction's panel (engineer, factory and upgrade-chain items, pause and repeat-build) and the keys of ReUI.Hotbuild sets. The base game's order panel is the same with or without ReUI

Feature: optional "Toggle Keybind Trainer" action in the keybinding window (category Mods)

Reads the keymap you are actually using and refreshes whenever you confirm new bindings

Only the left mouse button is ever refused; right clicks keep working. Does nothing in replays or while observing.

]]
