-- EndHub compatibility bootstrap for executors with partial API support.
-- This file is intentionally separate from loader.lua so the normal EndHub
-- path used by the owner stays untouched.

local G = _G
local sharedTable = rawget(G, "shared") or shared

-- Provide getgenv only when the executor does not already expose it.
if type(rawget(G, "getgenv")) ~= "function" then
    local compatEnv = type(sharedTable) == "table" and sharedTable or G
    G.getgenv = function()
        return compatEnv
    end
end

local ENV = getgenv()
ENV.ENDHUB_COMPAT = ENV.ENDHUB_COMPAT or {}
local Compat = ENV.ENDHUB_COMPAT

local function firstFunction(...)
    for i = 1, select("#", ...) do
        local fn = select(i, ...)
        if type(fn) == "function" then return fn end
    end
end

local function safeIndex(root, key)
    if type(root) ~= "table" then return nil end
    local ok, value = pcall(function() return root[key] end)
    return ok and value or nil
end

local executorName = "Unknown"
do
    local identify = firstFunction(rawget(G, "identifyexecutor"), rawget(G, "getexecutorname"))
    if identify then
        local ok, a, b = pcall(identify)
        if ok then executorName = tostring(a or b or "Unknown") end
    elseif type(rawget(G, "Xeno")) == "table" then
        executorName = "Xeno"
    end
end
Compat.Executor = executorName

-- Common naming differences. Never replace a working native implementation.
if type(rawget(G, "queue_on_teleport")) ~= "function" then
    local syn = rawget(G, "syn")
    local fluxus = rawget(G, "fluxus")
    local q = firstFunction(
        rawget(G, "queueonteleport"),
        safeIndex(syn, "queue_on_teleport"),
        safeIndex(fluxus, "queue_on_teleport")
    )
    if q then G.queue_on_teleport = q end
end

if type(rawget(G, "request")) ~= "function" then
    local syn = rawget(G, "syn")
    local http = rawget(G, "http")
    local req = firstFunction(
        rawget(G, "http_request"),
        safeIndex(http, "request"),
        safeIndex(syn, "request")
    )
    if req then G.request = req end
end

if type(rawget(G, "isrbxactive")) ~= "function" and type(rawget(G, "iswindowactive")) == "function" then
    G.isrbxactive = rawget(G, "iswindowactive")
end

-- Some UI libraries ask for gethui/cloneref even when CoreGui works normally.
if type(rawget(G, "cloneref")) ~= "function" then
    G.cloneref = function(v) return v end
end

if type(rawget(G, "gethui")) ~= "function" then
    G.gethui = function()
        return game:GetService("CoreGui")
    end
end

local function has(name)
    return type(rawget(G, name)) == "function"
end

local caps = {
    getgenv = has("getgenv"),
    loadstring = type(loadstring) == "function",
    queue = has("queue_on_teleport"),
    readfile = has("readfile"),
    writefile = has("writefile"),
    isfile = has("isfile"),
    isfolder = has("isfolder"),
    makefolder = has("makefolder"),
    request = has("request"),
    gethui = has("gethui"),
}
Compat.Capabilities = caps

local capParts = {}
for _, name in ipairs({"getgenv","loadstring","queue","readfile","writefile","isfile","isfolder","makefolder","request","gethui"}) do
    capParts[#capParts + 1] = name .. "=" .. (caps[name] and "OK" or "NO")
end
print("[EndHub Compat] executor=" .. executorName .. " | " .. table.concat(capParts, " | "))

assert(caps.loadstring, "[EndHub Compat] loadstring is unavailable in this executor")

local okHttp, loaderSource = pcall(function()
    return game:HttpGet(
        "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/loader.lua?v=" .. tostring(os.time()),
        true
    )
end)
assert(okHttp and type(loaderSource) == "string" and #loaderSource > 20,
    "[EndHub Compat] game:HttpGet failed: " .. tostring(loaderSource))

local fn, compileErr = loadstring(loaderSource, "EndHub compat -> loader.lua")
assert(fn, "[EndHub Compat] loader compile failed: " .. tostring(compileErr))

local okRun, result = pcall(fn)
if not okRun then
    warn("[EndHub Compat] EndHub failed: " .. tostring(result))
    error(result, 0)
end

print("[EndHub Compat] EndHub started successfully")
return result
