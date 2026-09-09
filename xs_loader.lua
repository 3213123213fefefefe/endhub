local base = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/"
local function run(path)
    local src = game:HttpGet(base .. path .. "?v=" .. tostring(os.time()))
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
-- Stop the retired Solara-only menu loop if an older loader was executed in
-- this same client. Otherwise it would survive and keep competing with main.
if type(ENV.ENDHUB_XS_MENU_STOP) == "function" then pcall(ENV.ENDHUB_XS_MENU_STOP) end
ENV.ENDHUB_XS_MENU_STOP, ENV.ENDHUB_XS_MENU_DRIVER = nil, nil
local live = ENV.ENDHUB
if live and live.Unload then pcall(function() live:Unload() end) end
ENV.ENDHUB, ENV.ENDHUB_BOOT, ENV.ENDHUB_WORK_LOADING = nil, nil, nil
task.wait(0.15)

local seed = run("solara_normal_route_seed.lua")
local hub = run("compat_loader.lua")

-- The normal EndHub already installs menu_first_screen_patch.lua. Keep its
-- exact Endure -> Slot 1 -> Current Server implementation intact on Solara.
-- Loading a second driver here used to replace MenuStep and fight that patch.
print("[EndHub Solara] using main Endure/menu controller")

if type(hub) == "table" and type(seed) == "table" and type(seed.Route) == "table" then
    local placeKey = "125503525638054"
    hub.Config = hub.Config or {}
    hub.Config.TrinketRoutes = type(hub.Config.TrinketRoutes) == "table" and hub.Config.TrinketRoutes or {}
    local current = hub.Config.TrinketRoutes[placeKey]
    if type(current) ~= "table" then current = {} hub.Config.TrinketRoutes[placeKey] = current end
    table.clear(current)
    for i, point in ipairs(seed.Route) do current[i] = {point[1], point[2], point[3]} end
    hub.Config.TrinketExplore = true
    local option = hub.UI and hub.UI.Options and hub.UI.Options.EH_TrinketRoutePoints
    if option and option.SetValues then
        local values = {}
        for i, point in ipairs(current) do
            values[#values + 1] = string.format("%d | %.1f, %.1f, %.1f", i, point[1], point[2], point[3])
        end
        pcall(function()
            option:SetValues(values)
            if #values > 0 and option.SetValue then option:SetValue(values[1]) end
        end)
    end
    if hub.PersistenceManager and hub.PersistenceManager.SaveConfig then
        pcall(function() hub.PersistenceManager.SaveConfig(true) end)
    end
    print("[EndHub Solara] live route injected | points=" .. tostring(#current))
end

return hub
