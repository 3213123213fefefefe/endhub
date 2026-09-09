-- EndHub menu-server-8 wrapper
-- Load the current Work build first, then patch only the two pre-server menu buttons.
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

hub.WorkMenuPatch = "menu-server-8"
print("[EndHub Loader] menu-server-8 | exact Main Play + Slot 1 direct activation | server screen preserved")
return hub
