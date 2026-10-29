-- Runs the REAL modules/panel.lua on a fake UI toolkit (extras/fake_ui.lua) with FAF's
-- real layouthelpers.lua: where the panel lands (left of the menu strip, never on
-- it), its collapse arrow, dragging along the three edges while the options window
-- is open, the saved position, the reset button, hiding with the interface, and
-- "no panel, no arrow" when it is turned off. LazyVars raise on circular layouts
-- exactly like FAF's, so every edge is laid out and every variable evaluated.
--
--     lua50 extras/test_panel.lua <path to a checkout of FAForever/fa>
--
-- It cannot say how the panel LOOKS (textures, fonts, the exact arrow art) or how
-- the engine's hit testing treats it.

local fa = arg[1]
assert(fa, 'pass the path of a FAForever/fa checkout (for layouthelpers.lua)')
dofile('extras/harness.lua')
dofile('extras/fake_ui.lua')
Harness.Mount('/mods/KeybindTrainer', '.')
local MOD = '/mods/KeybindTrainer'

local Say = print
local passed, failed = 0, 0
local function Check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1 Say('  FAIL  ' .. name) end
end
local function Near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

local P, cfg, toggles

local function Fresh()
    Harness.Reset()
    FakeUI.Install(fa)
    _G.KeybindTrainerPath = MOD
    P = import(MOD .. '/modules/panel.lua')
    cfg = import(MOD .. '/modules/config.lua').Config
    toggles = 0
end
local function Make(enabled, blocked)
    P.Create(function() toggles = toggles + 1 end, enabled ~= false, blocked or 0)
    return P.Get()
end
local function Press(control, mods, extra)
    local event = { Type = 'ButtonPress', Modifiers = mods or { Left = true }, MouseX = 0, MouseY = 0, KeyCode = 'MB_Left' }
    if extra then for k, v in pairs(extra) do event[k] = v end end
    return control:HandleEvent(event)
end
local function Count(list) return list and table.getn(list) or 0 end
local function EvaluateAll(p)
    -- evaluate every layout variable of every part: a circular pair raises here
    local parts = { p.root, p.body, p.text }
    if p.arrow then table.insert(parts, p.arrow) end
    for _, tri in ipairs(p.hints or {}) do table.insert(parts, tri) end
    if p.reset then table.insert(parts, p.reset) end
    for _, c in ipairs(parts) do
        for _, n in ipairs({ 'Left', 'Top', 'Right', 'Bottom', 'Width', 'Height' }) do
            local v = c[n]()
            if type(v) ~= 'number' then error('no number for ' .. c.kind .. '.' .. n) end
        end
    end
    return true
end

--------------------------------------------------------------------------------
Say('== default spot: left of the menu strip')
Fresh()
local p = Make(true, 0)
Check('the panel exists with its arrow on the top edge', p and p.arrow and p.edge == 't' and p.arrow.edge == 't')
Check('every layout variable resolves (no circular dependency)', pcall(EvaluateAll, p))
local stripLeft = 960 - 90
Check('its right edge stops short of the menu strip (never on top of it)', p.root.Left() + p.root.Width() < stripLeft)
Check('...by the configured gap', Near(p.root.Left() + p.root.Width(), stripLeft - cfg.Panel.Gap))
Check('it hangs from the top of the screen', Near(p.root.Top(), 0) and Near(p.arrow.Top(), -3))
Check('its tab is centred over it', Near(p.arrow.Left() + p.arrow.Width() / 2, p.root.Left() + p.root.Width() / 2))
Check('the label sits under the tab', Near(p.body.Top(), p.arrow.Height() - 6) and Near(p.body.Left(), p.root.Left()))
-- layouthelpers floors to whole pixels, so allow one
Check('the panel text is 2 pixels below the middle of its box', math.abs(p.text.Top() - (p.body.Top() + (p.body.Height() - p.text.Height()) / 2 + 2)) <= 1)
Check('...there is no nudge setting any more', cfg.Panel.TextNudge == nil and cfg.Feedback.TextNudge == nil)
Check('the text is inside its box horizontally', p.text.Left() >= p.body.Left() and p.text.Left() + p.text.Width() <= p.body.Left() + p.body.Width())
Check('the label says ON, in gold', p.text.text == 'KEYBIND TRAINER: ON' and p.text.textColor == 'fffad400')

Say('== the note above a refused button')
Fresh()
local Feedback = import(MOD .. '/modules/feedback.lua')
local button = FakeUI.New(FakeUI.frame, 'bitmap')
button.Left:Set(500) button.Top:Set(500) button.Width:Set(40) button.Height:Set(40)
Check('default: the note stays 1 second', cfg.Feedback.ToastSeconds == 1)
Feedback.Notify(button, 'Q', 'Patrol')
local toast = FakeUI.frame.children[2]
local inner = toast and toast.children[1]
local keyLabel, nameLabel = inner and inner.children[1], inner and inner.children[2]
Check('a note appears with the key and what it is for', keyLabel and keyLabel.text == '[Q]' and nameLabel.text == 'Patrol')
Check('...every layout variable of it resolves', pcall(function()
    for _, c in ipairs({ toast, inner, keyLabel, nameLabel }) do
        for _, n in ipairs({ 'Left', 'Top', 'Right', 'Bottom', 'Width', 'Height' }) do if type(c[n]()) ~= 'number' then error(n) end end
    end end))
Check('...above the button it was for, centred on it', toast.Top() + toast.Height() < button.Top() and Near(toast.Left() + toast.Width() / 2, 520))
Check('both texts are 10 pixels below the middle of the note\'s box',
    math.abs(keyLabel.Top() - (inner.Top() + (inner.Height() - keyLabel.Height()) / 2 + 10)) <= 1
    and math.abs(nameLabel.Top() - (inner.Top() + (inner.Height() - nameLabel.Height()) / 2 + 10)) <= 1)
Check('the key label starts at the left padding and the name follows it', keyLabel.Left() > inner.Left() and nameLabel.Left() > keyLabel.Left() + keyLabel.Width() - 0.01)
Check('the button flashes red', (function() for _, c in ipairs(button.children) do if c.color == 'c0ff2a2a' then return true end end end)())
Check('the error sound plays', Count(FakeUI.sounds) == 1 and FakeUI.sounds[1].Cue == 'UI_Menu_Error_01')
-- Notify forks two threads: the red flash (0.5 s) first, then the note
Check('the flash lasts half a second', (function() FakeUI.threads[1]() return FakeUI.waits[1] == 0.5 end)())
Check('the note waits the configured 1 second before fading', (function() FakeUI.threads[2]() return FakeUI.waits[2] == 1 end)())
cfg.Feedback.ToastSeconds = 4
Feedback.Notify(button, 'W', 'Build Land Factory')
Feedback.Notify(button, 'E', 'Build Mex')
Check('a second refusal replaces the first note (only one on screen)', (function()
    local n = 0
    for _, c in ipairs(FakeUI.frame.children) do
        if c.kind == 'bitmap' and c.children[1] and c.children[1].children[1] and c.children[1].children[1].kind == 'text' then n = n + 1 end
    end
    return n == 1 end)())
FakeUI.threads[table.getn(FakeUI.threads)]()
Check('a longer setting is honoured', FakeUI.waits[table.getn(FakeUI.waits) - 1] == 4)

Say('== the menu strip is not there / is a different width')
Fresh()
FakeUI.tabs.controls.bgTop = {}
p = Make()
Check('no recorded width: falls back to 180 (still left of the strip)', Near(p.root.Left() + p.root.Width(), 960 - 90 - cfg.Panel.Gap))
Fresh()
FakeUI.tabs.controls = nil
p = Make()
Check('no menu strip at all: still placed, no error', p and Near(p.root.Left() + p.root.Width(), 960 - 90 - cfg.Panel.Gap))
Fresh()
FakeUI.tabs.controls.bgTop.defWidth = 360    -- a 2x UI scale makes the strip twice as wide
p = Make()
Check('a wider (scaled) strip moves the panel further left', Near(p.root.Left() + p.root.Width(), 960 - 180 - cfg.Panel.Gap))

Say('== label and width')
Fresh()
p = Make(true, 0)
local right = p.root.Left() + p.root.Width()
local width = p.body.Width()
P.Refresh(true, 12)
Check('the count shows', p.text.text == 'KEYBIND TRAINER: ON  |  12 blocked')
Check('...the panel grew and kept its right edge off the strip (it grows leftwards)', p.body.Width() > width and Near(p.root.Left() + p.root.Width(), right))
P.Refresh(false, 12)
Check('OFF is worded and coloured differently', p.text.text == 'KEYBIND TRAINER: OFF' and p.text.textColor == 'ff9aa0a6')
P.Refresh(true, 0)
Check('ON is gold', p.text.textColor == 'fffad400')
Check('clicking the label toggles the trainer', (function() Press(p.body) return toggles == 1 end)())
Press(p.body, { Right = true })
Check('...only with the left button', toggles == 1)
p.body:HandleEvent({ Type = 'MouseEnter' })
Check('hovering the label shows its tooltip', Count(FakeUI.tooltips) == 1)
p.body:HandleEvent({ Type = 'MouseExit' })
Check('...and leaving it takes it down', Count(FakeUI.tooltips) == 0)

Say('== collapsing')
Fresh()
p = Make()
Check('starts unfolded', p.body:IsHidden() == false and p.arrow:IsChecked() == false)
Press(p.arrow)
Check('clicking the arrow folds the panel to just the tab', p.body:IsHidden() and not p.arrow:IsHidden() and p.arrow:IsChecked())
Check('...with the fold sound', Count(FakeUI.sounds) >= 1)
Check('...the tab stays where it was', Near(p.arrow.Top(), -3))
Press(p.arrow)
Check('clicking again opens it', not p.body:IsHidden() and not p.arrow:IsChecked())
Press(p.arrow)
local oldRoot = p.root
P.Rebuild()
p = P.Get()
Check('a rebuild keeps it folded', p.body:IsHidden() and p.arrow:IsChecked() and IsDestroyed(oldRoot))

Fresh()
cfg.Panel.StartCollapsed = true
p = Make()
Check('Panel.StartCollapsed: starts folded, arrow shows folded', p.body:IsHidden() and p.arrow:IsChecked() and not p.arrow:IsHidden())
Press(p.arrow)
Check('...and still opens', not p.body:IsHidden())

Say('== no panel at all')
Fresh()
cfg.Panel.Show = false
p = Make()
Check('Panel.Show = false: nothing is built (no panel, no arrow)', p == false and Count(FakeUI.frame.children) == 0)
cfg.Panel.Show = true
P.Rebuild()
p = P.Get()
Check('...turning it back on builds it, arrow included', p and p.arrow and Count(FakeUI.frame.children) == 1)
local root = p.root
cfg.Panel.Show = false
P.Rebuild()
Check('turning it off in a running game removes all of it', P.Get() == false and IsDestroyed(root) and Count(FakeUI.frame.children) == 0)
P.SetEditing(true)
Check('...and the options window being open does not bring it back', P.Get() == false)
P.SetEditing(false)

Say('== editing (the ReUI options window is open)')
Fresh()
p = Make()
Check('not editing: no drag hints and no reset button', p.hints == nil and p.reset == nil)
Press(p.arrow)
Check('...and pressing the tab just folds', FakeUI.dragger == nil and p.collapsed == true)
Press(p.arrow)
P.SetEditing(true)
p = P.Get()
Check('editing: the little triangles show', Count(p.hints) == 2)
Check('...and a Reset position button', p.reset ~= nil)
Check('...all laid out without a circular dependency', pcall(EvaluateAll, p))
p.arrow:HandleEvent({ Type = 'MouseEnter' })
Check('...hovering the tab explains the drag', Count(FakeUI.tooltips) == 1 and FakeUI.tooltips[1].text == 'Move the panel')
Check('right button never drags', (function() Press(p.arrow, { Right = true }) return FakeUI.dragger == nil end)())
Check('left press on the tab starts a drag', (function() return Press(p.arrow) == true and FakeUI.dragger ~= nil end)())

local drag = FakeUI.dragger
drag.OnMove(drag, 1, 1)
Check('a tiny wobble is not a drag', P.Get() == p and P.layout.place == false)
drag.OnMove(drag, 30, 600)
p = P.Get()
Check('dragged near the left edge: the panel moves to the left edge', P.layout.place.edge == 'l' and p.edge == 'l' and p.arrow.edge == 'l')
Check('...hard against the screen edge, tab just off it', Near(p.root.Left(), 0) and Near(p.arrow.Left(), -3))
Check('...centred on the pointer vertically', Near(p.root.Top() + p.root.Height() / 2, 600) or math.abs(p.root.Top() + p.root.Height() / 2 - 600) < 1)
Check('...body clear of the tab', p.body.Left() >= p.arrow.Left() + p.arrow.Width() - 6 - 0.01)
Check('...everything resolves on the left edge', pcall(EvaluateAll, p))
Check('...hints point up and down there (wide and short)', Count(p.hints) == 2 and p.hints[1].Width() > p.hints[1].Height())

drag.OnMove(drag, 1900, 300)
p = P.Get()
Check('dragged to the right edge', P.layout.place.edge == 'r' and p.edge == 'r' and p.arrow.edge == 'r')
Check('...flush with the right edge, tab just off it', Near(p.root.Left() + p.root.Width(), 1920) and Near(p.arrow.Left() + p.arrow.Width(), 1920 + 3))
Check('...everything resolves on the right edge', pcall(EvaluateAll, p))

drag.OnMove(drag, 700, 4)
p = P.Get()
Check('dragged to the top edge', P.layout.place.edge == 't' and p.edge == 't')
Check('...centred on the pointer along the top', Near(p.root.Left() + p.root.Width() / 2, 700))
Check('...everything resolves on the top edge', pcall(EvaluateAll, p))
local saves = FakeUI.saved or 0
drag.OnRelease(drag, 700, 4)
Check('releasing after a drag saves the spot', FakeUI.prefs.KeybindTrainerPanelPlace and FakeUI.prefs.KeybindTrainerPanelPlace.edge == 't' and (FakeUI.saved or 0) == saves + 1)

drag.OnMove(drag, 0, 540)
p = P.Get()
Check('at the very top-left corner / edges nothing leaves the screen', p.root.Left() >= -0.01 and p.root.Top() >= -0.01
    and p.root.Left() + p.root.Width() <= 1920.01 and p.root.Top() + p.root.Height() <= 1080.01)
drag.OnMove(drag, 1920, 1080)
p = P.Get()
Check('...nor at the bottom-right', p.root.Left() + p.root.Width() <= 1920.01 and p.root.Top() + p.root.Height() <= 1080.01 and p.root.Top() >= -0.01)
drag.OnCancel(drag)

Say('== a click on the tab while editing')
FakeUI.dragger = nil
p = P.Get()
local before = p.collapsed
Press(p.arrow)
FakeUI.dragger.OnRelease(FakeUI.dragger, 0, 0)
Check('a press and release without moving folds it, as a click should', P.Get().collapsed == (not before))
Check('...and does not save a spot', true)

Say('== reset')
Fresh()
p = Make()
P.SetEditing(true)
p = P.Get()
Press(p.arrow)
FakeUI.dragger.OnMove(FakeUI.dragger, 40, 500)
FakeUI.dragger.OnRelease(FakeUI.dragger, 40, 500)
Check('moved and saved', FakeUI.prefs.KeybindTrainerPanelPlace.edge == 'l')
p = P.Get()
Press(p.reset)
p = P.Get()
Check('Reset position puts it back left of the menu strip', p.edge == 't' and Near(p.root.Left() + p.root.Width(), 960 - 90 - cfg.Panel.Gap))
Check('...and forgets the saved spot', FakeUI.prefs.KeybindTrainerPanelPlace == nil)
Check('...and is still in editing mode', p.reset ~= nil and Count(p.hints) == 2)
P.SetEditing(false)
p = P.Get()
Check('closing the options window removes the hints and the button', p.hints == nil and p.reset == nil)
Check('...and the tab no longer drags', (function() FakeUI.dragger = nil Press(p.arrow) return FakeUI.dragger == nil end)())

Say('== remembered spot')
Fresh()
FakeUI.prefs.KeybindTrainerPanelPlace = { edge = 'r', along = 0.5 }
p = Make()
Check('a saved spot is used at the next start', p.edge == 'r' and Near(p.root.Left() + p.root.Width(), 1920) and Near(p.root.Top(), (1080 - p.root.Height()) * 0.5))
Fresh()
FakeUI.prefs.KeybindTrainerPanelPlace = { edge = 'x', along = 0.5 }
p = Make()
Check('a bad edge in the profile is ignored', p.edge == 't' and Near(p.root.Left() + p.root.Width(), 960 - 90 - cfg.Panel.Gap))
Fresh()
FakeUI.prefs.KeybindTrainerPanelPlace = { edge = 'l', along = 0 / 0 }
p = Make()
Check('...and so is a NaN position', p.edge == 't')
Fresh()
FakeUI.prefs.KeybindTrainerPanelPlace = { edge = 'l', along = 7 }
p = Make()
Check('a position beyond the screen is pulled back onto it', p.edge == 'l' and p.root.Top() + p.root.Height() <= 1080.01)
Fresh()
FakeUI.prefs.KeybindTrainerPanelPlace = 'junk'
p = Make()
Check('junk in the profile is ignored', p.edge == 't')

Say('== screen capture mode')
Fresh()
p = Make()
FakeUI.gameMain.gameUIHidden = true
P.SetUIHidden()
Check('hidden with the rest of the interface', p.root:IsHidden() and p.hidden == true)
FakeUI.gameMain.gameUIHidden = false
P.SetUIHidden()
Check('shown again with it', not p.root:IsHidden() and not p.body:IsHidden())
Press(p.arrow)
FakeUI.gameMain.gameUIHidden = true
P.SetUIHidden()
FakeUI.gameMain.gameUIHidden = false
P.SetUIHidden()
Check('a folded panel is still folded afterwards (Show() shows every child)', p.body:IsHidden() and not p.arrow:IsHidden())
FakeUI.gameMain.gameUIHidden = true
P.Rebuild()
Check('a panel built while the interface is hidden starts hidden', P.Get().root:IsHidden())
FakeUI.gameMain.gameUIHidden = false

Say('== tidy up')
Fresh()
p = Make()
local r = p.root
P.Destroy()
Check('Destroy removes everything', P.Get() == false and IsDestroyed(r) and Count(FakeUI.frame.children) == 0)
Check('Refresh after Destroy is harmless', pcall(P.Refresh, true, 3))
Check('so is SetUIHidden / SetEditing / Rebuild with nothing made', pcall(P.SetUIHidden) and pcall(P.SetEditing, true) and pcall(P.Rebuild))
Fresh()
p = Make()
Check('Create twice leaves one panel', (function() local first = P.Get().root Make() return IsDestroyed(first) and Count(FakeUI.frame.children) == 1 end)())

Say(string.format('\n%d passed, %d failed', passed, failed))
os.exit(failed == 0 and 0 or 1)
