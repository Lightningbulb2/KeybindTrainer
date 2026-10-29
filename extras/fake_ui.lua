-- A fake of the bits of FAF's UI toolkit the panel uses, for tests on stock Lua 5.0.
--
-- What is faithful (it is what makes the tests worth running):
--   * LazyVars cache, are invalidated through what they depend on, and raise
--     "circular dependency" exactly where FAF's would;
--   * a Control starts with FAF's circular default layout (Left/Right/Width and
--     Top/Bottom/Height each defined from the others) until four are set;
--   * Hide() hides a control, Show() shows it AND every child (the engine does:
--     a folded panel has to be re-folded after a Show);
--   * FAF's real layouthelpers.lua runs on top of it (Harness.files).
-- What is not: anything about drawing, textures, hit testing order or sound.
--
-- Usage:  dofile('extras/harness.lua'); dofile('extras/fake_ui.lua'); FakeUI.Install(fa)
--         where fa is a checkout of FAForever/fa (for layouthelpers.lua).

FakeUI = {}

--------------------------------------------------------------------------------
-- LazyVar
--------------------------------------------------------------------------------
local LV = {}
LV.__index = LV
local current = nil

local function IsLazy(v) return type(v) == 'table' and getmetatable(v) == LV end

local function NewVar(initial)
    local v = setmetatable({ value = nil, fn = nil, busy = false, uses = {}, usedBy = {} }, LV)
    if initial ~= nil then v:Set(initial) end
    return v
end

LV.__call = function(self)
    if self.fn and self.value == nil then
        if self.busy then
            error('circular dependency in lazy evaluation', 2)
        end
        for used in pairs(self.uses) do used.usedBy[self] = nil end
        self.uses = {}
        self.busy = true
        local previous = current
        current = self
        local ok, result = pcall(self.fn)
        current = previous
        self.busy = false
        if not ok then error(result, 0) end
        self.value = result
    end
    if current and current ~= self then
        current.uses[self] = true
        self.usedBy[current] = true
    end
    return self.value
end

local function Dirty(var, seen)
    for dependent in pairs(var.usedBy) do
        if not seen[dependent] then
            seen[dependent] = true
            if dependent.fn then dependent.value = nil end
            Dirty(dependent, seen)
        end
    end
end

function LV.Set(self, v)
    for used in pairs(self.uses) do used.usedBy[self] = nil end
    self.uses = {}
    if type(v) == 'function' then
        self.fn, self.value = v, nil
    elseif IsLazy(v) then
        self.fn, self.value = function() return v() end, nil
    else
        self.fn, self.value = nil, v
    end
    Dirty(self, {})
end
LV.SetFunction = LV.Set
LV.SetValue = LV.Set

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------
local Methods = {}
local Meta = { __index = Methods }

local function IsDestroyedFn(c)
    return c == nil or c == false or c.destroyed == true
end

local function ResetLayout(c)
    c.Left:Set(function() return c.Right() - c.Width() end)
    c.Top:Set(function() return c.Bottom() - c.Height() end)
    c.Right:Set(function() return c.Left() + c.Width() end)
    c.Bottom:Set(function() return c.Top() + c.Height() end)
    c.Width:Set(function() return c.Right() - c.Left() end)
    c.Height:Set(function() return c.Bottom() - c.Top() end)
end

local function New(parent, kind)
    local c = { kind = kind, parent = parent, children = {}, hidden = false, destroyed = false,
        alpha = 1, hitTest = true, name = nil }
    for _, n in ipairs({ 'Left', 'Top', 'Right', 'Bottom', 'Width', 'Height', 'Depth' }) do
        c[n] = NewVar()
    end
    setmetatable(c, Meta)
    ResetLayout(c)
    c.Depth:Set(function() return parent and parent.Depth() + 1 or 0 end)
    if parent then table.insert(parent.children, c) end
    return c
end

function Methods.Hide(self) self.hidden = true end
local function ShowAll(c)
    c.hidden = false
    for _, child in ipairs(c.children) do ShowAll(child) end
end
function Methods.Show(self) ShowAll(self) end
function Methods.IsHidden(self)
    local c = self
    while c do
        if c.hidden then return true end
        c = c.parent
    end
    return false
end
function Methods.Destroy(self)
    self.destroyed = true
    for _, child in ipairs(self.children) do child:Destroy() end
    if self.parent then
        for i, c in ipairs(self.parent.children) do
            if c == self then table.remove(self.parent.children, i) break end
        end
    end
end
function Methods.DisableHitTest(self) self.hitTest = false end
function Methods.EnableHitTest(self) self.hitTest = true end
function Methods.SetSolidColor(self, color) self.color = color end
function Methods.SetAlpha(self, a) self.alpha = a end
function Methods.GetTopmostDepth(self) return 100 end
function Methods.HandleEvent(self, event) return false end

-- Text
function Methods.SetText(self, text)
    self.text = text
    self.Width:Set(string.len(text) * self.size * 0.5)
end
function Methods.SetColor(self, color) self.textColor = color end
function Methods.GetStringAdvance(self, s) return string.len(s) * self.size * 0.5 end

-- Checkbox (the collapse arrow)
function Methods.SetCheck(self, checked, silent)
    self.checked = checked and true or false
    if not silent and self.OnCheck then self:OnCheck(self.checked) end
end
function Methods.IsChecked(self) return self.checked and true or false end
function Methods.ToggleCheck(self) self:SetCheck(not self.checked) end

local function Constructor(kind)
    return setmetatable({}, { __call = function(_, parent, name)
        local c = New(parent, kind)
        c.name = name
        return c
    end })
end

--------------------------------------------------------------------------------
-- install
--------------------------------------------------------------------------------
function FakeUI.Install(fa)
    FakeUI.frame = New(nil, 'frame')
    FakeUI.frame.Left:Set(0)
    FakeUI.frame.Top:Set(0)
    FakeUI.frame.Width:Set(1920)
    FakeUI.frame.Height:Set(1080)
    FakeUI.frame.Depth:Set(0)

    GetFrame = function() return FakeUI.frame end
    IsDestroyed = IsDestroyedFn
    -- FAF's class helpers, used by layouthelpers.lua's fluent Layouter (which the mod does not use)
    local function MakeClass(spec)
        spec = spec or {}
        return setmetatable(spec, { __call = function(c) return setmetatable({}, { __index = c }) end })
    end
    ClassSimple = MakeClass
    Class = function(...) return MakeClass end
    iscallable = function(v) return type(v) == 'function' or (type(v) == 'table' and getmetatable(v) ~= nil and getmetatable(v).__call ~= nil) end
    GetTextureDimensions = function() return 24, 15 end
    PlaySound = function(s) table.insert(FakeUI.sounds, s) end
    Sound = function(t) return t end
    SavePreferences = function() FakeUI.saved = (FakeUI.saved or 0) + 1 end
    PostDragger = function(frame, keycode, drag) FakeUI.dragger = drag end
    FakeUI.sounds = {}
    FakeUI.threads, FakeUI.waits, FakeUI.fades = {}, {}, {}
    ForkThread = function(fn) table.insert(FakeUI.threads, fn) end   -- run by hand: FakeUI.threads[n]()
    WaitSeconds = function(s) table.insert(FakeUI.waits, s) end
    FakeUI.tooltips = {}
    FakeUI.prefs = { options = { ui_scale = 1 } }
    FakeUI.gameMain = { gameUIHidden = false }
    FakeUI.tabs = { controls = { bgTop = { defWidth = 180 } } }

    local arrowSize = { t = { 24, 15 }, l = { 15, 24 }, r = { 15, 24 } }
    local UIUtil = {
        bodyFont = 'Arial',
        CreateText = function(parent, text, size, font, shadow)
            local c = New(parent, 'text')
            c.size = size
            c.Height:Set(size * 1.2)
            c:SetText(text)
            return c
        end,
        CreateCollapseArrow = function(parent, position)
            if position ~= 't' and position ~= 'r' and position ~= 'l' then error('bad edge ' .. tostring(position), 2) end
            local c = New(parent, 'arrow')
            c.edge = position
            c.Width:Set(arrowSize[position][1])
            c.Height:Set(arrowSize[position][2])
            c.checked = false
            c.HandleEvent = function(self, event)
                if event.Type == 'ButtonPress' then
                    self:SetCheck(not self.checked)
                    return true
                end
                return false
            end
            return c
        end,
    }

    local O = Harness.overrides
    O['/lua/maui/bitmap.lua'] = { Bitmap = Constructor('bitmap') }
    O['/lua/maui/group.lua'] = { Group = Constructor('group') }
    O['/lua/ui/uiutil.lua'] = UIUtil
    O['/lua/maui/effecthelpers.lua'] = { FadeOut = function(control, time, a, b) table.insert(FakeUI.fades, control) end }
    O['/lua/ui/game/tooltip.lua'] = {
        CreateMouseoverDisplay = function(parent, tip) table.insert(FakeUI.tooltips, tip) end,
        DestroyMouseoverDisplay = function() FakeUI.tooltips = {} end,
        AddCheckboxTooltip = function() end,
    }
    O['/lua/maui/dragger.lua'] = { Dragger = function() return {} end }
    O['/lua/ui/game/tabs.lua'] = FakeUI.tabs
    O['/lua/ui/game/gamemain.lua'] = FakeUI.gameMain
    O['/lua/user/prefs.lua'] = {
        GetFromCurrentProfile = function(k) return FakeUI.prefs[k] end,
        SetToCurrentProfile = function(k, v) FakeUI.prefs[k] = v end,
    }
    Harness.files['/lua/maui/layouthelpers.lua'] = fa .. '/lua/maui/layouthelpers.lua'
end

FakeUI.New = New
FakeUI.NewVar = NewVar
