--******************************************************************************
--** Keybind Trainer -- modules/panel.lua
--**
--** The small panel with the trainer's ON / OFF label and the number of refused
--** clicks. Click the label to switch the trainer on or off.
--**
--** The collapsing and dragging are those of Sim Speed Balancer's panel and
--** TeamMouse's panel (same code shape, same profile keys style):
--**   * FAF's own collapse tab ("the arrow", as the score panel has) folds the
--**     panel down to just the tab. Checked means folded.
--**   * While ReUI's options window for this mod is open (SetEditing), pressing
--**     and dragging the tab moves the panel along the left, right or top edge of
--**     the screen (little triangles show the ways it can go), and a "Reset
--**     position" button appears under the panel. A click without a drag still
--**     folds / opens it. Where it was put is kept in the profile.
--**   * Hidden along with the rest of the interface in screen capture mode.
--**   * Config.Panel.Show = false (a ReUI option): no panel and no arrow at all.
--**
--** Where it starts: to the LEFT of the game's menu strip (the pause / menu tabs
--** at the top centre of the screen), not on top of it. The strip is 180 (scaled)
--** pixels wide when it is closed; it widens when its menu opens, so this goes by
--** its closed width and the panel does not slide about.
--**
--** Layout notes (LazyVars): Left and Top are always the only inputs; Width and
--** Height only ever come from the controls inside, never from Left/Top, so no
--** pair can end up circular.
--**
--** Nothing here may break the game: callers pcall every entry point.
--******************************************************************************

local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local Group = import('/lua/maui/group.lua').Group
local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Tooltip = import('/lua/ui/game/tooltip.lua')

local Path = rawget(_G, 'KeybindTrainerPath') or '/mods/KeybindTrainer'
local Config = import(Path .. '/modules/config.lua').Config

-- How far the panel's text sits below the middle of its box, in pixels (scaled with
-- the UI).
local TEXT_DOWN = 2

local PLACE_KEY = 'KeybindTrainerPanelPlace'
local ON_COLOR = 'fffad400'
local OFF_COLOR = 'ff9aa0a6'
local BACK_COLOR = 'c8101419'
local HINT_COLOR = 'ffffd24a'

local S = LayoutHelpers.ScaleNumber

--- The controls, once built (false: no panel).
local panel = false

--- What the panel shows and does, kept so it can be rebuilt.
local source = false

--- place: false for the usual spot (left of the menu strip), or { edge, along }: the
--- edge ('l', 'r' or 't') and how far along it, 0..1 of the room there is.
--- loaded: place has been read from the profile. editing: ReUI's options window is
--- open. collapsed: folded (nil until the panel is first made: Config.Panel.StartCollapsed).
layout = { place = false, loaded = false, editing = false, collapsed = nil }

--------------------------------------------------------------------------------
-- small things
--------------------------------------------------------------------------------

--- Whether the game's interface is hidden (screen capture mode).
local function UIHidden()
    local ok, GameMain = pcall(import, '/lua/ui/game/gamemain.lua')
    return ok and type(GameMain) == 'table' and GameMain.gameUIHidden and true or false
end

local function Play(cue)
    pcall(function() PlaySound(Sound({ Cue = cue, Bank = 'Interface' })) end)
end

local function Label(enabled, blocked)
    if enabled then
        if blocked > 0 then
            return 'KEYBIND TRAINER: ON  |  ' .. blocked .. ' blocked'
        end
        return 'KEYBIND TRAINER: ON'
    end
    return 'KEYBIND TRAINER: OFF'
end

--- Half the width of the game's menu strip when it is closed (unscaled 180, scaled).
local function MenuHalfWidth()
    local ok, half = pcall(function()
        local bgTop = import('/lua/ui/game/tabs.lua').controls.bgTop
        return (bgTop.defWidth or S(180)) / 2
    end)
    if ok and type(half) == 'number' then
        return half
    end
    return S(90)
end

--- The edge the panel is on. The usual spot hangs from the top edge.
local function Edge()
    return layout.place and layout.place.edge or 't'
end

local function Fraction(v, room)
    if room <= 0 then
        return 0
    end
    return math.max(0, math.min(1, v / room))
end

--------------------------------------------------------------------------------
-- where it is (kept in the profile)
--------------------------------------------------------------------------------

local function LoadPlace()
    if layout.loaded then
        return
    end
    layout.loaded = true
    pcall(function()
        local saved = import('/lua/user/prefs.lua').GetFromCurrentProfile(PLACE_KEY)
        if type(saved) == 'table' and (saved.edge == 'l' or saved.edge == 'r' or saved.edge == 't')
            and type(saved.along) == 'number' and saved.along == saved.along then
            layout.place = { edge = saved.edge, along = math.max(0, math.min(1, saved.along)) }
        end
    end)
end

local function SavePlace()
    pcall(function()
        local place = layout.place
        import('/lua/user/prefs.lua').SetToCurrentProfile(PLACE_KEY,
            place and { edge = place.edge, along = place.along } or nil)
        SavePreferences()
    end)
end

--- Put the panel's root where layout.place says (none: left of the menu strip).
local function Place(root)
    local frame = GetFrame(0)
    local place = layout.place
    if not place then
        root.Left:Set(function()
            return frame.Left() + frame.Width() / 2 - MenuHalfWidth() - root.Width() - S(Config.Panel.Gap)
        end)
        root.Top:Set(function() return frame.Top() end)
        return
    end

    local along = place.along
    if place.edge == 't' then
        root.Left:Set(function() return frame.Left() + (frame.Width() - root.Width()) * along end)
        root.Top:Set(function() return frame.Top() end)
        return
    end
    if place.edge == 'r' then
        root.Left:Set(function() return frame.Left() + frame.Width() - root.Width() end)
    else
        root.Left:Set(function() return frame.Left() end)
    end
    root.Top:Set(function() return frame.Top() + (frame.Height() - root.Height()) * along end)
end

--------------------------------------------------------------------------------
-- folding
--------------------------------------------------------------------------------

--- Show what should be shown: only the tab when folded. Show() shows every child,
--- so after showing the whole panel again the folded state is put back.
local function ApplyFolded()
    if not panel then
        return
    end
    local collapsed = layout.collapsed and true or false
    panel.collapsed = collapsed
    if collapsed then
        panel.body:Hide()
    else
        panel.body:Show()
    end
    if panel.arrow and panel.arrow.IsChecked and panel.arrow:IsChecked() ~= collapsed then
        panel.arrow:SetCheck(collapsed, true)
    end
end

local function ApplyHidden()
    if not panel then
        return
    end
    local hidden = UIHidden()
    panel.hidden = hidden
    if hidden then
        panel.root:Hide()
    else
        panel.root:Show()
        ApplyFolded()
    end
end

--------------------------------------------------------------------------------
-- the tab: folds, and drags while the options window is open
--------------------------------------------------------------------------------

local function Tip(control, tip)
    pcall(function()
        if control then
            Tooltip.CreateMouseoverDisplay(control, tip or { text = 'Move the panel',
                body = 'Drag this tab along the left, right or top edge of the screen. Click it to fold the panel.' },
                0.3, true)
        else
            Tooltip.DestroyMouseoverDisplay()
        end
    end)
end

--- A small solid triangle pointing 'u', 'd', 'l' or 'r', from lines of bitmaps
--- (no texture to go missing).
local function Triangle(parent, dir)
    local tri = Group(parent)
    if dir == 'u' or dir == 'd' then
        LayoutHelpers.SetDimensions(tri, 7, 4)
    else
        LayoutHelpers.SetDimensions(tri, 4, 7)
    end
    tri:DisableHitTest()
    for i = 0, 3 do
        local line = Bitmap(tri)
        line:SetSolidColor(HINT_COLOR)
        line:DisableHitTest()
        if dir == 'u' or dir == 'd' then
            LayoutHelpers.AtLeftTopIn(line, tri, 3 - i, dir == 'u' and i or 3 - i)
            LayoutHelpers.SetDimensions(line, 2 * i + 1, 1)
        else
            LayoutHelpers.AtLeftTopIn(line, tri, dir == 'l' and i or 3 - i, 3 - i)
            LayoutHelpers.SetDimensions(line, 1, 2 * i + 1)
        end
    end
    return tri
end

--- Little triangles either side of the tab: the ways it can be dragged.
local function DragHints(root, arrow, edge)
    local function Hang(tri, left, top)
        tri.Left:Set(left)
        tri.Top:Set(top)
        tri.Depth:Set(function() return arrow.Depth() + 1 end)
        return tri
    end
    if edge == 't' then
        local a, b = Triangle(root, 'l'), Triangle(root, 'r')
        local function Middle(tri)
            return function() return arrow.Top() + (arrow.Height() - tri.Height()) / 2 end
        end
        return {
            Hang(a, function() return arrow.Left() - a.Width() - 2 end, Middle(a)),
            Hang(b, function() return arrow.Left() + arrow.Width() + 2 end, Middle(b)),
        }
    end
    local a, b = Triangle(root, 'u'), Triangle(root, 'd')
    local function Centre(tri)
        return function() return arrow.Left() + (arrow.Width() - tri.Width()) / 2 end
    end
    return {
        Hang(a, Centre(a), function() return arrow.Top() - a.Height() - 2 end),
        Hang(b, Centre(b), function() return arrow.Top() + arrow.Height() + 2 end),
    }
end

--- A small "Reset position" button under the panel (over it if there is no room
--- under it), while the options window is open. Folds away with the panel.
local function ResetButton(body, edge)
    local frame = GetFrame(0)
    local back = Bitmap(body)
    back:SetSolidColor(BACK_COLOR)
    LayoutHelpers.SetDimensions(back, 96, 18)
    if edge == 'r' then
        back.Left:Set(function() return body.Left() + body.Width() - back.Width() end)
    elseif edge == 't' then
        back.Left:Set(function() return body.Left() + (body.Width() - back.Width()) / 2 end)
    else
        back.Left:Set(function() return body.Left() end)
    end
    back.Top:Set(function()
        local below = body.Top() + body.Height() + 2
        if below + back.Height() > frame.Top() + frame.Height() then
            return body.Top() - back.Height() - 2
        end
        return below
    end)

    local text = UIUtil.CreateText(back, 'Reset position', 10, UIUtil.bodyFont, true)
    text:SetColor('ffaaaaaa')
    text:DisableHitTest()
    LayoutHelpers.AtCenterIn(text, back, TEXT_DOWN)

    back.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            text:SetColor('ffffffff')
        elseif event.Type == 'MouseExit' then
            text:SetColor('ffaaaaaa')
        elseif event.Type == 'ButtonPress' then
            Play('UI_Menu_MouseDown_Sml')
            ResetPlace()
            return true
        end
        return false
    end
    return back
end

local Build

--- The tab dragged to (x, y): onto the nearest of the three edges, with the tab
--- under the pointer. A new edge needs a new tab: rebuilt.
function DragTo(x, y)
    local frame = GetFrame(0)
    if not panel or not frame then
        return
    end
    local fl, ft, fw, fh = frame.Left(), frame.Top(), frame.Width(), frame.Height()
    local edge, nearest = 'l', x - fl
    if fl + fw - x < nearest then
        edge, nearest = 'r', fl + fw - x
    end
    if y - ft < nearest then
        edge = 't'
    end
    -- The panel's size on the edge it is going TO: the tab hangs above the body on
    -- the top edge and beside it on the others (the tab turns a quarter when the
    -- orientation changes), so the size differs between them.
    local bw, bh = panel.body.Width(), panel.body.Height()
    local tabW, tabH = 0, 0
    if panel.arrow then
        tabW, tabH = panel.arrow.Width(), panel.arrow.Height()
        if (edge == 't') ~= (panel.edge == 't') then
            tabW, tabH = tabH, tabW
        end
        tabW, tabH = tabW - S(6), tabH - S(6)
    end
    local w, h
    if edge == 't' then
        w, h = bw, tabH + bh
    else
        w, h = tabW + bw, bh
    end
    local along
    if edge == 't' then
        along = Fraction(x - fl - w / 2, fw - w)
    else
        along = Fraction(y - ft - h / 2, fh - h)
    end
    local was = Edge()
    layout.place = { edge = edge, along = along }
    if edge ~= was then
        Build()
    else
        Place(panel.root)
    end
end

--- A press on the tab while the options window is open: a drag moves the panel,
--- a click without moving folds or opens it as usual.
local function StartDrag(event)
    local ok, DraggerModule = pcall(import, '/lua/maui/dragger.lua')
    local post = rawget(_G, 'PostDragger')
    if not ok or type(DraggerModule) ~= 'table' or not DraggerModule.Dragger or not post then
        return false
    end
    local drag = DraggerModule.Dragger()
    local startX, startY = event.MouseX or 0, event.MouseY or 0
    local moved = false
    drag.OnMove = function(self, x, y)
        if not moved and math.abs(x - startX) + math.abs(y - startY) < 4 then
            return
        end
        moved = true
        DragTo(x, y)
    end
    drag.OnRelease = function(self, x, y)
        if moved then
            SavePlace()
        elseif panel and panel.arrow then
            panel.arrow:SetCheck(not panel.collapsed)
        end
        if self.Destroy then self:Destroy() end
    end
    drag.OnCancel = function(self)
        if moved then
            SavePlace()
        end
        if self.Destroy then self:Destroy() end
    end
    post(GetFrame(0), event.KeyCode, drag)
    return true
end

--- Fold / unfold from the tab.
local function OnArrowCheck(checked)
    layout.collapsed = checked and true or false
    ApplyFolded()
    Play(checked and 'UI_Score_Window_Close' or 'UI_Score_Window_Open')
end

--- Set up the tab on its edge: folds the panel, and while editing drags it.
local function SetUpTab(arrow, edge)
    arrow:EnableHitTest(true)
    arrow.OnCheck = function(self, checked)
        OnArrowCheck(checked)
    end
    pcall(function() Tooltip.AddCheckboxTooltip(arrow, { text = 'Collapse/Expand' }) end)

    local handle = arrow.HandleEvent
    arrow.HandleEvent = function(self, event)
        if layout.editing then
            local t = event.Type
            if (t == 'ButtonPress' or t == 'ButtonDClick')
                and not (event.Modifiers and event.Modifiers.Right) and StartDrag(event) then
                return true
            elseif t == 'MouseEnter' then
                local result = handle and handle(self, event) or false
                Tip(self)
                return result
            elseif t == 'MouseExit' then
                Tip()
            end
        end
        if handle then
            return handle(self, event)
        end
        return false
    end
end

--------------------------------------------------------------------------------
-- building it
--------------------------------------------------------------------------------

local function DestroyControls()
    if panel then
        pcall(function() panel.root:Destroy() end)
        panel = false
    end
end

Build = function()
    DestroyControls()
    if not source or not Config.Panel.Show then
        return
    end
    local frame = GetFrame(0)
    if not frame then
        return
    end
    LoadPlace()
    local edge = Edge()

    local root = Group(frame, 'KeybindTrainerPanel')
    root:DisableHitTest()
    root.Depth:Set(frame:GetTopmostDepth() + 5)

    -- FAF's own tab, on the edge the panel is on. Checked means folded.
    local okArrow, arrow = pcall(UIUtil.CreateCollapseArrow, root, edge)
    if not okArrow then
        arrow = false
    end

    -- Everything that folds away.
    local body = Bitmap(root)
    body:SetSolidColor(BACK_COLOR)

    local text = UIUtil.CreateText(body, Label(source.enabled, source.blocked), 12, UIUtil.bodyFont, true)
    text:DisableHitTest(true)
    LayoutHelpers.AtCenterIn(text, body, TEXT_DOWN)

    body.Width:Set(function() return text.Width() + S(16) end)
    body.Height:Set(S(18))

    -- How far the tab pokes in beside / above the body (it hangs just past the
    -- screen's edge, as FAF puts its own).
    local function ArrowW() return arrow and arrow.Width() - S(6) or 0 end
    local function ArrowH() return arrow and arrow.Height() - S(6) or 0 end

    if edge == 't' then
        root.Width:Set(function() return body.Width() end)
        root.Height:Set(function() return ArrowH() + body.Height() end)
        body.Left:Set(function() return root.Left() end)
        body.Top:Set(function() return root.Top() + ArrowH() end)
        if arrow then
            arrow.Left:Set(function() return root.Left() + (root.Width() - arrow.Width()) / 2 end)
            arrow.Top:Set(function() return root.Top() - S(3) end)
        end
    else
        root.Width:Set(function() return ArrowW() + body.Width() end)
        root.Height:Set(function() return body.Height() end)
        body.Top:Set(function() return root.Top() end)
        if edge == 'r' then
            body.Left:Set(function() return root.Left() end)
        else
            body.Left:Set(function() return root.Left() + ArrowW() end)
        end
        if arrow then
            if edge == 'r' then
                arrow.Left:Set(function() return root.Left() + root.Width() - arrow.Width() + S(3) end)
            else
                arrow.Left:Set(function() return root.Left() - S(3) end)
            end
            arrow.Top:Set(function() return root.Top() + (root.Height() - arrow.Height()) / 2 end)
        end
    end
    Place(root)

    if arrow then
        arrow.Depth:Set(function() return root.Depth() + 10 end)
    end

    -- Click the label: the trainer on / off.
    local onToggle = source.onToggle
    body.HandleEvent = function(self, event)
        if event.Type == 'ButtonPress' and event.Modifiers and event.Modifiers.Left then
            Tip()
            if onToggle then onToggle() end
            return true
        elseif event.Type == 'MouseEnter' then
            Tip(self, { text = 'Keybind Trainer',
                body = 'Click to turn the trainer on or off.\nWhile it is on, buttons that have a keybind cannot be clicked.' })
            return true
        elseif event.Type == 'MouseExit' then
            Tip()
            return true
        end
        return false
    end

    panel = { root = root, body = body, text = text, arrow = arrow, edge = edge, collapsed = false,
        hidden = false }
    if arrow then
        SetUpTab(arrow, edge)
        if layout.editing then
            panel.hints = DragHints(root, arrow, edge)
        end
    end
    if layout.editing then
        panel.reset = ResetButton(body, edge)
    end

    -- Folded or not: carried across rebuilds, else the setting.
    if layout.collapsed == nil then
        layout.collapsed = Config.Panel.StartCollapsed and true or false
    end
    ApplyFolded()

    -- Built while the interface is hidden: stay hidden with it.
    if UIHidden() then
        ApplyHidden()
    end
    Refresh(source.enabled, source.blocked)
end

--------------------------------------------------------------------------------
-- public
--------------------------------------------------------------------------------

--- Make the panel. onToggle() runs when its label is clicked.
---@param onToggle function
---@param enabled boolean
---@param blocked number
function Create(onToggle, enabled, blocked)
    Destroy()
    source = { onToggle = onToggle, enabled = enabled, blocked = blocked }
    Build()
end

--- Update the wording and colour (cheap; does nothing without a panel).
function Refresh(enabled, blocked)
    if source then
        source.enabled, source.blocked = enabled, blocked
    end
    if not panel or IsDestroyed(panel.root) then
        return
    end
    panel.text:SetText(Label(enabled, blocked))
    panel.text:SetColor(enabled and ON_COLOR or OFF_COLOR)
end

--- Build it again: a setting that is only read when it is made changed (Show).
function Rebuild()
    Build()
end

--- ReUI's options window for this mod opened or closed.
---@param on boolean
function SetEditing(on)
    on = on and true or false
    if layout.editing == on then
        return
    end
    layout.editing = on
    Tip()
    Build()
end

--- Back to the usual spot, and forget the saved one.
function ResetPlace()
    layout.place = false
    SavePlace()
    Build()
end

--- The interface was hidden or shown (screen capture mode): follow it.
function SetUIHidden()
    ApplyHidden()
end

--- For the tests.
function Get()
    return panel
end

function Destroy()
    DestroyControls()
    source = false
    layout.collapsed = nil
end
