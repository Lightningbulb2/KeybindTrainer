--******************************************************************************
--** Keybind Trainer -- modules/feedback.lua
--**
--** Everything the player sees when a click is refused:
--**   * a floating "[Q]  Patrol" note above the button
--**   * a short red flash on the button
--**   * the game's standard "not allowed" sound
--** (The ON / OFF panel is its own module: panel.lua.)
--**
--** Layout notes (all learned from core FAF UI code):
--**   - Left/Top are pinned to plain numbers and Width/Height are bound to the
--**     text, so no LazyVar pair is ever left circular.
--**   - Every Bitmap has a solid colour, and decorative ones have hit-testing
--**     disabled once, at construction (never toggled).
--**   - Nothing here may break a click: callers wrap every entry point in pcall.
--******************************************************************************

local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Effect = import('/lua/maui/effecthelpers.lua')

local Path = rawget(_G, 'KeybindTrainerPath') or '/mods/KeybindTrainer'
local Config = import(Path .. '/modules/config.lua').Config

-- How far the note's text sits below the middle of its box, in pixels (scaled with
-- the UI). A text control's box has room for descenders and reads high otherwise.
local TEXT_DOWN = 10

local KEY_COLOR = 'fffad400'
local BORDER_COLOR = 'ffd9a400'
local PANEL_COLOR = 'f0101419'
local FLASH_COLOR = 'c0ff2a2a'

-- Everything lives in one table: cheap to reset, and no extra upvalues.
local ui = { toast = false, token = 0 }

--------------------------------------------------------------------------------
-- toast
--------------------------------------------------------------------------------

local function DestroyToast()
    if ui.toast and not IsDestroyed(ui.toast) then
        ui.toast:Destroy()
    end
    ui.toast = false
end

local function ShowToast(control, keyText, label)
    DestroyToast()

    local frame = GetFrame(0)
    ui.token = ui.token + 1
    local token = ui.token

    local border = Bitmap(frame)
    border:SetSolidColor(BORDER_COLOR)
    border:DisableHitTest(true)
    border.Depth:Set(frame:GetTopmostDepth() + 10)

    local inner = Bitmap(border)
    inner:SetSolidColor(PANEL_COLOR)
    inner:DisableHitTest(true)
    LayoutHelpers.FillParentFixedBorder(inner, border, 1)

    local keyLabel = UIUtil.CreateText(inner, '[' .. keyText .. ']', 16, UIUtil.bodyFont, true)
    keyLabel:SetColor(KEY_COLOR)
    keyLabel:DisableHitTest(true)

    local full = label

    local nameLabel = UIUtil.CreateText(inner, full, 14, UIUtil.bodyFont, true)
    nameLabel:SetColor('ffffffff')
    nameLabel:DisableHitTest(true)

    LayoutHelpers.AtLeftIn(keyLabel, inner, 10)
    LayoutHelpers.AtVerticalCenterIn(keyLabel, inner, TEXT_DOWN)
    LayoutHelpers.RightOf(nameLabel, keyLabel, 8)
    LayoutHelpers.AtVerticalCenterIn(nameLabel, inner, TEXT_DOWN)

    local padding = LayoutHelpers.ScaleNumber(10 + 8 + 10 + 2)
    border.Width:Set(function() return keyLabel.Width() + nameLabel.Width() + padding end)
    border.Height:Set(LayoutHelpers.ScaleNumber(30))

    -- Centre it above the clicked control, nudged back on screen if need be.
    local width = border.Width()
    local height = border.Height()
    local margin = LayoutHelpers.ScaleNumber(4)
    local x = control.Left() + (control.Width() - width) / 2
    local y = control.Top() - height - LayoutHelpers.ScaleNumber(6)
    if y < margin then
        y = control.Top() + control.Height() + LayoutHelpers.ScaleNumber(6)
    end
    if x < margin then x = margin end
    if x + width > frame.Width() - margin then x = frame.Width() - margin - width end
    border.Left:Set(x)
    border.Top:Set(y)

    ui.toast = border

    ForkThread(function()
        WaitSeconds(Config.Feedback.ToastSeconds)
        if token ~= ui.token or IsDestroyed(border) then return end
        Effect.FadeOut(border, 0.4, 1, 0)
        WaitSeconds(0.45)
        if token == ui.token and not IsDestroyed(border) then
            border:Destroy()
            ui.toast = false
        end
    end)
end

--------------------------------------------------------------------------------
-- flash
--------------------------------------------------------------------------------

local function ShowFlash(control)
    local flash = Bitmap(control)
    flash:SetSolidColor(FLASH_COLOR)
    flash:DisableHitTest(true)
    LayoutHelpers.FillParent(flash, control)
    LayoutHelpers.DepthOverParent(flash, control, 50)
    Effect.FadeOut(flash, 0.4, 1, 0)

    ForkThread(function()
        WaitSeconds(0.5)
        if not IsDestroyed(flash) then
            flash:Destroy()
        end
    end)
end

--------------------------------------------------------------------------------
-- public: one call per refused click
--------------------------------------------------------------------------------

--- Show the player why nothing happened.
---@param control Control  the button that was clicked
---@param keyText string   friendly key, e.g. 'Shift + Q'
---@param label string     what the button does, e.g. 'Patrol'
function Notify(control, keyText, label)
    if Config.Feedback.Sound then
        pcall(function()
            PlaySound(Sound({ Cue = 'UI_Menu_Error_01', Bank = 'Interface' }))
        end)
    end
    if Config.Feedback.Flash then
        local ok, err = pcall(ShowFlash, control)
        if not ok then LOG('KeybindTrainer: flash failed: ' .. tostring(err)) end
    end
    if Config.Feedback.Toast then
        local ok, err = pcall(ShowToast, control, keyText, label)
        if not ok then LOG('KeybindTrainer: toast failed: ' .. tostring(err)) end
    end
end

--- Tear everything down (called when the game UI is destroyed).
function Destroy()
    ui.token = ui.token + 1
    DestroyToast()
end
