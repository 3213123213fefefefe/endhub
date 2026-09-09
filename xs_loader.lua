local base = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/"
local function run(path)
    local src = game:HttpGet(base .. path .. "?v=" .. tostring(os.time()))
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
local live = ENV.ENDHUB
if live and live.Unload then pcall(function() live:Unload() end) end
ENV.ENDHUB, ENV.ENDHUB_BOOT, ENV.ENDHUB_WORK_LOADING = nil, nil, nil
task.wait(0.15)

local seed = run("solara_normal_route_seed.lua")
local menuDriver = run("xs_menu_entry.lua")
local hub = run("compat_loader.lua")

-- Once the regular controller exists, make the Solara driver authoritative.
-- This prevents two different routines from clicking the same menu.
if type(hub) == "table" and hub.ServerCycle and menuDriver then
    local normalMenuStep = hub.ServerCycle.MenuStep
    menuDriver.Managed = true
    hub.ServerCycle.MenuStep = function()
        local hasMenu = menuDriver.Step()
        if hasMenu then return true end
        -- Keep the normal in-game/menu-clear confirmation but do not let it
        -- click another GUI while the external driver owns a visible menu.
        if type(normalMenuStep) == "function" then return normalMenuStep() end
        return false
    end
    print("[EndHub Solara] staged menu driver attached")
end

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
