-- Shared test harness: a tiny stand-in for FAF's module system, runnable on stock
-- Lua 5.0. Like FAF, every module file runs in its own environment table, paths
-- are case-insensitive, and each module's own `import` resolves relative paths
-- ('config.lua') against the module's folder.
--
--   Harness.Mount(virtualFolder, realFolder)   make a folder on disk importable
--   Harness.overrides   virtual file -> table returned instead of loading it
--   Harness.import      the global import

Harness = {}
Harness.modules = {}
Harness.overrides = {}
Harness.files = {}      -- lowercased virtual path -> real path on disk
Harness.logs = {}

local function ReadFile(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end
Harness.ReadFile = ReadFile

--- Make every file under `realDir` importable as `virtualDir/<same relative path>`
--- (matched case-insensitively, as the game's VFS does).
function Harness.Mount(virtualDir, realDir)
    local p = io.popen('find "' .. realDir .. '" -type f -name "*.lua"')
    local prefix = string.len(realDir)
    for line in p:lines() do
        local rel = string.sub(line, prefix + 1)
        if string.sub(rel, 1, 1) ~= '/' then rel = '/' .. rel end
        Harness.files[string.lower(virtualDir .. rel)] = line
    end
    p:close()
end

--- Load a file into the given environment. LuaPlus-only operators are rewritten
--- so FAF's and ReUI's own files load on stock Lua 5.0.
function Harness.LoadInto(path, env)
    local src = ReadFile(path)
    assert(src, 'cannot read ' .. path)
    src = string.gsub(src, '!=', '~=')
    local fn, err = loadstring(src, '@' .. path)
    assert(fn, err)
    setmetatable(env, { __index = _G })
    setfenv(fn, env)
    fn()
    return env
end

--- Collapse 'a/b/../c' -> '/a/c'.
local function Collapse(path)
    local out = {}
    for part in string.gfind(path, '[^/]+') do
        if part == '..' then
            table.remove(out)
        elseif part ~= '.' then
            table.insert(out, part)
        end
    end
    return '/' .. table.concat(out, '/')
end

local function Dir(path)
    return (string.gsub(path, '/[^/]*$', ''))
end

local function Override(lower)
    for key, value in pairs(Harness.overrides) do
        if string.lower(key) == lower then return value end
    end
end

function Harness.import(path)
    path = string.lower(path)
    local o = Override(path)
    if o then return o end
    if Harness.modules[path] then return Harness.modules[path] end

    local real = Harness.files[path]
    assert(real, 'nothing mounted at ' .. path)

    local env = {}
    env.import = function(p)
        if string.sub(p, 1, 1) ~= '/' then
            p = Collapse(Dir(path) .. '/' .. p)
        end
        return Harness.import(p)
    end
    Harness.modules[path] = env
    Harness.LoadInto(real, env)
    return env
end

--- Forget loaded modules and overrides (mounts stay).
function Harness.Reset()
    Harness.modules = {}
    Harness.overrides = {}
    Harness.logs = {}
end

-- engine-ish globals the mod expects
import = Harness.import
LOG  = function(s) table.insert(Harness.logs, 'LOG ' .. tostring(s)) end
WARN = function(s) table.insert(Harness.logs, 'WARN ' .. tostring(s)) end
LOC  = function(s) local _, _, x = string.find(tostring(s), '^<LOC [^>]*>(.*)$') return x or s end
