-- EndHub menu-server-8 wrapper
-- Load the current Work build, patch Endure, then apply lightweight runtime optimizations.
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))

local workURL = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/work_loader.lua?v=" .. nonce
local workSource = game:HttpGet(workURL)
local workFn, workErr = loadstring(workSource)
assert(workFn, "[EndHub menu8] work loader compile error: " .. tostring(workErr))
local hub = workFn()
assert(hub and hub.ServerCycle, "[EndHub menu8] Work build did not return ServerCycle")

local patchURL = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/modules/menu_first_screen_patch.lua?v=" .. nonce
local patchSource = game:HttpGet(patchURL)
local patchFn, patchErr = loadstring(patchSource)
assert(patchFn, "[EndHub menu8] patch compile error: " .. tostring(patchErr))
local init = patchFn()
assert(type(init) == "function", "[EndHub menu8] invalid first-screen patch")
init(hub)

-- The temporary PickupSpy is intentionally NOT loaded in normal operation.
-- Its global __namecall hook was useful for discovery, but keeping that hook
-- installed all session adds unnecessary overhead now that PickupDrop is known.
local fpsURL = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/modules/fps_patch.lua?v=" .. nonce
local fpsSource = game:HttpGet(fpsURL)
local fpsFn, fpsErr = loadstring(fpsSource)
if fpsFn then
    local fpsInit = fpsFn()
    if type(fpsInit) == "function" then
        local ok, err = pcall(fpsInit, hub)
        if not ok then warn("[EndHub menu8] FPS patch init error: " .. tostring(err)) end
    end
else
    warn("[EndHub menu8] FPS patch compile error: " .. tostring(fpsErr))
end

hub.WorkMenuPatch = "menu-server-8-fps"
print("[EndHub Loader] menu-server-8-fps | Endure + server flow + lightweight runtime")
return hub
