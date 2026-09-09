local base = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/"
local function run(path)
    local src = game:HttpGet(base .. path .. "?v=" .. tostring(os.time()))
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end
run("xs_menu_entry.lua")
local bot = run("xeno_solara_trinket.lua")
run("xs_embedded_route.lua")
return bot
