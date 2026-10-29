--******************************************************************************
--** Keybind Trainer -- hook/lua/ui/game/orders.lua
--**
--** The order buttons are Checkbox controls whose OnClick is the order's
--** behaviour function. They are destroyed and rebuilt on every selection change
--** (SetAvailableOrders) and on a layout change (SetLayout), so after each of
--** those we walk the button grid and wrap every button's OnClick.
--**
--** Hotkeys never click these buttons: they start a command mode or call
--** orders.lua functions directly, so a refused click cannot block a keybind.
--**
--** Only module globals are used (SetAvailableOrders, SetLayout, controls).
--******************************************************************************

local function KbtTrainer()
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
    return import(path .. '/modules/trainer.lua')
end

local function KbtCheck(control, modifiers)
    return KbtTrainer().CheckOrder(control, modifiers)
end

local function KbtWrapOrderButton(item)
    if item.KbtWrapped then
        return
    end
    local original = item.OnClick
    item.OnClick = function(self, modifiers)
        local ok, blocked = pcall(KbtCheck, self, modifiers)
        if ok and blocked then
            return
        end
        return original(self, modifiers)
    end
    item.KbtWrapped = true
end

local function KbtWrapOrderButtons()
    local grid = controls and controls.orderButtonGrid
    if not grid then
        return
    end
    local cols, rows = grid:GetDimensions()
    for row = 1, rows do
        for col = 1, cols do
            local item = grid:GetItem(col, row)
            if item and item._data then
                KbtWrapOrderButton(item)
            end
        end
    end
end

local KbtOriginalSetAvailableOrders = SetAvailableOrders
function SetAvailableOrders(availableOrders, availableToggles, newSelection)
    KbtOriginalSetAvailableOrders(availableOrders, availableToggles, newSelection)
    local ok, err = pcall(KbtWrapOrderButtons)
    if not ok then
        LOG('KeybindTrainer: could not wrap the order buttons: ' .. tostring(err))
    end
end

local KbtOriginalSetLayout = SetLayout
function SetLayout(layout)
    KbtOriginalSetLayout(layout)
    local ok, err = pcall(KbtWrapOrderButtons)
    if not ok then
        LOG('KeybindTrainer: could not wrap the order buttons: ' .. tostring(err))
    end
end
