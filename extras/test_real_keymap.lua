-- Runs keybinds.lua against FAF's REAL data files.
-- Usage:  lua50 extras/test_real_keymap.lua <path to a checkout of FAForever/fa>
local fa = arg[1]
assert(fa, 'pass the path of a FAForever/fa checkout')
dofile('extras/harness.lua')

-- FAF's table.combine (merge any number of tables, later ones win)
function table.combine(...)
    local out = {}
    for i = 1, arg.n do
        for k, v in pairs(arg[i]) do out[k] = v end
    end
    return out
end
Harness.Mount('/mods/KeybindTrainer', '.')

local function Load(rel)
    local env = {}
    Harness.LoadInto(fa .. '/lua/' .. rel, env)
    return env
end

local groups  = Load('keymap/unitkeygroups.lua').unitkeygroups
local actions = Load('keymap/keyactions.lua').keyActions
local hotbuild = Load('keymap/hotbuildKeyMap.lua').defaultKeyMap
local tooltips = Load('ui/help/tooltips.lua').Tooltips

local K = import('/mods/KeybindTrainer/modules/keybinds.lua')
K.Invalidate()
local c = K.Build(hotbuild, actions, groups, tooltips)
-- install it as the live cache by faking the engine glue
Harness.overrides['/lua/keymap/keymapper.lua'] = { GetCurrentKeyMap = function() return hotbuild end, GetKeyActions = function() return actions end }
Harness.overrides['/lua/keymap/unitkeygroups.lua'] = { unitkeygroups = groups }
Harness.overrides['/lua/ui/help/tooltips.lua'] = { Tooltips = tooltips }
K.Invalidate()

local fails = 0
local function Expect(name, got, want)
    if got == want then
        print(string.format('  ok    %-44s %s', name, tostring(got)))
    else
        fails = fails + 1
        print(string.format('  FAIL  %-44s got %s, want %s', name, tostring(got), tostring(want)))
    end
end

print('== orders (default FAF hotbuild keymap)')
Expect('patrol',            K.GetOrderKey('patrol'),   'Q')
Expect('reclaim',           K.GetOrderKey('reclaim'),  'A')
Expect('assist (guard)',    K.GetOrderKey('assist'),   'I')
Expect('overcharge',        K.GetOrderKey('overcharge'), 'O')
Expect('stop',              K.GetOrderKey('stop'),     'Esc')
Expect('mode (fire toggle: never locked)', K.GetOrderKey('mode'), nil)
Expect('mode_hold_fire (its tooltip name)', K.GetOrderKey('mode_hold_fire'), nil)
Expect('move (unbound by default)', K.GetOrderKey('move'), nil)
Expect('attack (unbound by default)', K.GetOrderKey('attack'), nil)
Expect('unknown helpText',  K.GetOrderKey('does_not_exist'), nil)
Expect('pause button',      K.GetPanelKey('pause'),    'Tab')
Expect('repeat build button', K.GetPanelKey('repeat_build'), 'Z')

print('== build menu')
Expect('upgrade key',       K.GetUpgradeKey(), 'M')
Expect('UEF land factory ueb0101', K.GetBuildKey('ueb0101'), 'W')
Expect('Cybran air factory urb0102', K.GetBuildKey('urb0102'), 'W')
Expect('case-insensitive id', K.GetBuildKey('UEB0101'), 'W')
Expect('T1 engineer uel0105',  K.GetBuildKey('uel0105'), 'W')
Expect('UEF T1 mass extractor ueb1103', K.GetBuildKey('ueb1103'), 'S')
Expect('unknown blueprint', K.GetBuildKey('zzz9999'), nil)

print('== display')
Expect('Shift-Q', K.Display('Shift-Q'), 'Shift + Q')
Expect('Ctrl-Alt-R', K.Display('Ctrl-Alt-R'), 'Ctrl + Alt + R')
Expect('LeftBracket', K.Display('LeftBracket'), '[')
Expect('NumPlus', K.Display('NumPlus'), 'Num +')
Expect('Alt-RightClick', K.Display('Alt-RightClick'), 'Alt + Right Click')
Expect('translate hook', K.Display('Esc', function(t) if t == 'Esc' then return 'Escape' end end), 'Escape')

local nb, nid = 0, 0
for _ in pairs(c.byAction) do nb = nb + 1 end
for _ in pairs(c.byId) do nid = nid + 1 end
print(string.format('\nkeymap actions bound: %d, blueprint ids covered by a hotbuild key: %d', nb, nid))
print(fails == 0 and 'ALL OK' or (fails .. ' FAILED'))
os.exit(fails == 0 and 0 or 1)
