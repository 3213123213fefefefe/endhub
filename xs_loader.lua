local base = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/"
local function run(path)
    local src = game:HttpGet(base .. path .. "?v=" .. tostring(os.time()))
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end

-- Seed the owner's 28-point trinket route into the normal EndHub profile first,
-- then boot the normal EndHub through the compatibility shim. This keeps the
-- full regular EndHub UI/features instead of the small standalone XS window.
run("solara_normal_route_seed.lua")
return run("compat_loader.lua")
