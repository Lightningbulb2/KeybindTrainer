# Keybind Trainer

A UI-only FAF mod that makes you learn your keybinds by taking away the mouse alternative.

While the trainer is **ON**, any button whose action has a key bound to it **cannot be clicked**. Instead you get a note above the button telling you which key to press, a red flash, and the standard "not allowed" sound. Buttons with no keybind keep working normally.

```
   [Q]  Patrol      <- appears above the button you clicked
```

## Install

Copy the `KeybindTrainer` folder to

```
Documents\My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods\
```

so that `mods\KeybindTrainer\mod_info.lua` exists, then enable it in the in-game Mod Manager (UI mods are enabled on your side only, no one else needs it and it cannot desync a game).

Before publishing, edit `author` and `url` in `mod_info.lua`. Keep the folder name `KeybindTrainer` (ReUI finds the mod by it).

## What gets locked

| Button | Locked when | Default | Hint shown |
|---|---|---|---|
| Order panel (patrol, reclaim, stop, guard, capture, overcharge, dive, transport, nukes, shield/intel/stealth toggles, ...) | the matching action has a key | on | that key |
| Attack Move | always (see below) | on | Alt + Right Click |
| **Building construction**: structure icons in the build menu | the structure is in a bound hotbuild group | on | the key of its narrowest group |
| **Building upgrades**: the upgrade icon of a selected building | the "upgrade" hotbuild key is bound | **off** | that key |
| **Units** in factory / gateway / carrier menus | the unit is in a bound hotbuild group | **off** | the key of its narrowest group |
| Pause button | `pause_unit` has a key | on | that key |
| Repeat-build button | `toggle_repeat_build` has a key | on | that key |

The **return fire / hold fire / ground fire toggle is never locked**, whatever is bound to it.

Upgrades and units are off by default so upgrading and queueing units with the mouse stays free while you learn the construction and order keys. Switch **Building upgrades** / **Units in factories** on (ReUI options, or `Lock.Upgrades` / `Lock.Units` in `modules/config.lua`) when you want those locked too. Constructing a building and upgrading one are separate switches, so you can lock either without the other.

Rules that keep it from getting in your way:

- **Only a plain left click is refused.** Right-clicks (dequeue, target priority, distribute assist, dock damaged...) always work.
- **Clicking an already-active order button still cancels it** (Patrol, Reclaim, ...), because cancelling isn't "using" the order.
- **Disabled buttons, replays, and observing:** the trainer does nothing.
- **It reads the keymap you are really using**, including the default preset if you never saved your own, and refreshes whenever you confirm new bindings in the keybinding window. Rebind or unbind something and the lock follows immediately.
- **Fail open:** if anything inside the mod throws an error, the click goes through as normal. The mod can never be the reason an order isn't given.

> **Heads-up about the stock keymap.** FAF's default hotbuild keymap leaves **Move and Attack unbound** (you right-click to move). Those buttons will therefore stay clickable until you bind them in the keybinding window (F1). Attack Move has no keymap entry at all; FAF hard-wires it to Alt + Right Click, and the trainer locks it by default (`Lock.AttackMove` in the config).

## The panel

A small panel with `KEYBIND TRAINER: ON | 12 blocked` sits **to the left of the game's menu strip** at the top of the screen (beside it, not over it). Click its label to switch the trainer off/on; the choice is remembered per profile.

- **Fold it:** it has FAF's own collapse arrow, like the score panel. Click the arrow and the panel folds down to just the tab. (`Panel.StartCollapsed`, "Panel starts folded" in ReUI, starts every game folded.)
- **Move it:** with ReUI installed, open ReUI's options window and select *Keybind Trainer*. While that page is open, **press and drag the arrow** along the left, right or top edge of the screen (little triangles show which ways it can go). A *Reset position* button appears under the panel to put it back beside the menu strip. A click on the arrow without dragging still folds it. The spot is kept in your profile.
- **Hide it altogether:** untick **Show the panel** in the ReUI options (or `Panel.Show = false`): no panel and no collapse arrow at all. You can still bind a key to *Toggle Keybind Trainer*.
- Like the rest of the interface, it disappears in screen capture mode.

Optional key: press **F1** and look in the **Mods** category for *Toggle Keybind Trainer*. It has no key by default; bind one if you want a keyboard toggle. (The mod adds this entry to your profile's user key actions the first time it runs.)

Tip: turn on FAF's own **Hotkey Labels** option so each button also shows its key all the time, not only after a refused click. (FAF builds those labels from your *saved* keymap, so they can stay blank until you have saved one in the keybinding window. The trainer's own note does not depend on that.)

## Configuration

Everything is in `modules/config.lua` (restart the game after editing): which button kinds are locked, toast duration, sound/flash/toast on or off, hiding the panel, folding it at the start, the gap beside the menu strip, not adding the key action, silencing the startup line, the ReUI-visible toggles and the note's length (default 1 second). The text positions are fixed: the panel's text sits 2 pixels below the middle of its box and the note's text 10 (the `TEXT_DOWN` constant at the top of `modules/panel.lua` and `modules/feedback.lua`).

## ReUI

ReUI is optional. With it installed:

- **Settings:** a *Keybind Trainer* page appears in ReUI's options window with every setting above, each with a tooltip (orders, attack move, building construction, building upgrades, units, pause, repeat build, the note, flash, sound, the panel and whether it starts folded...). Changes apply immediately; *Save* keeps them, *Cancel* undoes them. `config.lua` supplies the defaults, and what you save in ReUI wins over it. The trainer's own ON/OFF is not in that window: it is a live in-game switch (the panel / key), remembered per profile. The same page is where the panel can be dragged (see above).
- **Panel replacements:**

| ReUI part | What the trainer does |
|---|---|
| **ReUI.Construction** (replaces the build menu) | Locks its engineer/commander menu, its factory menu (including structure upgrades), its upgrade chain, and its pause and repeat-build buttons, with the same rules and the same Buildings / Units switches. In its engineer menu *any* mouse button builds, so any button is refused there. |
| ReUI.ActionsPanel | Nothing to lock: it is an extra grid of selection actions, not the orders panel. |
| The orders panel | No ReUI mod replaces it, so it is the base game's panel with or without ReUI. |
| **ReUI.Hotbuild** | Its build sets and the keys you bound to them count as keybinds, so the icons they cover lock too. (A set you edit without re-confirming your keybindings is picked up at the next game start.) |
| Everything else (Economy, Minimap, Reclaim, Score, Templates...) | Not involved. |

The mod must be in a folder called exactly `KeybindTrainer` for ReUI to find it. Without ReUI, or without ReUI.Construction, nothing changes: the base game's panels are covered by the normal hooks.

## How it works

| File | Job |
|---|---|
| `hook/lua/ui/game/orders.lua` | after every order-panel rebuild, wraps each button's `OnClick` |
| `hook/lua/ui/game/construction.lua` | wraps the build-menu click handler and the pause / repeat-build buttons |
| `hook/lua/ui/game/gamemain.lua` | starts the trainer once the UI exists, tears it down with it, hides the panel in screen capture mode |
| `hook/lua/keymap/hotkeylabels.lua` | drops the cached keymap whenever FAF re-initialises its key tables |
| `Main.lua`, `Options.lua` | ReUI's entry points (never run without ReUI) |
| `modules/options.lua` | the settings list: ReUI window, defaults from `config.lua`, live apply |
| `modules/reui.lua` | locks ReUI.Construction's panel (build/upgrade items, pause, repeat) |
| `modules/keybinds.lua` | "which key is bound to this button?" (pure logic, no UI) |
| `modules/trainer.lua` | the decision logic, on/off state, persistence |
| `modules/feedback.lua` | the note above a refused button, flash, sound |
| `modules/panel.lua` | the ON/OFF panel: collapse arrow, dragging, reset, saved spot, placement beside the menu strip |

Why hotkeys can't be blocked by mistake: keybinds never click these buttons. They start command modes or call module functions directly, so refusing a click is purely a mouse-side decision. (The one non-mouse caller of the build-menu click handler, the build-template keys, passes no modifiers and is always allowed.)

## Testing

Run from the mod folder on a **stock Lua 5.0** interpreter (the game's dialect; the reference notes explain how to build one):

```
lua50 extras/test_logic.lua        # base-game hooks + decision logic, mocked engine
lua50 extras/test_reui.lua         # ReUI options, window hand-off, entry points, panel patch, Hotbuild keys (fake ReUI)
lua50 extras/test_reui_real.lua <path to 4z0t/FAF-UI-Mods checkout>
                                   # patches ReUI.Construction's REAL classes and clicks them
lua50 extras/test_panel.lua <path to FAForever/fa checkout>
                                   # the real panel.lua on a fake toolkit with FAF's real layouthelpers.lua
lua50 extras/test_real_keymap.lua <path to FAForever/fa checkout>
                                   # the resolver on FAF's real keyactions / unitkeygroups / default keymap
```

What this covers: every file loads on real Lua 5.0 (both number types); the resolver gives the right keys for real FAF data (patrol = Q, reclaim = A, factories and engineers = W, mex = S, upgrade = M, pause = Tab, repeat = Z); right-click, cancel, disabled, replay, observer, off-switch, fail-open and no-double-wrapping all behave; buildings vs units; the keymap refresh; ReUI's option values and window (ReUI.Options 2.0, which the mod requires); ReUI's real build-menu classes are found, refused when they should be, and run normally when they should; the panel lands beside (never on) the menu strip, no layout on any edge is circular, folding, dragging to each edge, the saved spot, reset, hiding with the interface and "no panel, no arrow" all behave.

What it **cannot** cover, and was **not tested in a running game**: how the note / flash / panel look and where the text sits at your UI scale, the exact art of the collapse arrow, ReUI's window rendering, drag feel, and the live behaviour of the hooked FAF and ReUI functions. Everything was written against current FAF (Oct 2026) and ReUI (Core 1.7, Options 2.0) source and each API used was looked up there, but the first run in a real match is the real test.

## If something looks wrong

Open the game log and search for `KeybindTrainer`. Every failure path logs a line and then lets the click through:

- `could not read the keymap, nothing will be locked` — the keymap APIs changed; nothing will be locked.
- `could not wrap the order buttons` / `the panel buttons` — a FAF refactor moved something; those buttons stay clickable.
- `startup failed, the trainer is disabled for this session` — the whole mod stays out of the way.
- `ReUI.Construction ...: locked` / `NOT patched (...)` — printed once per game when ReUI.Construction is installed; a `NOT patched` line means ReUI changed shape and only that part of its panel stays unlocked.
- `ReUI panel support failed` / `ReUI.Hotbuild sets not read` — the ReUI extras are skipped, the base game lock is unaffected.
- `flash failed` / `toast failed` — the lock still works, only the visual note is missing.

To uninstall, remove the folder. If you bound a key to *Toggle Keybind Trainer*, unbind it first: the action stays in your profile and would have nothing to run once the mod is gone.
