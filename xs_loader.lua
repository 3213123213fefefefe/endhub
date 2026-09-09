local base = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/"
local function run(path)
    local src = game:HttpGet(base .. path .. "?v=" .. tostring(os.time()))
    local fn, err = loadstring(src)
    assert(fn, err)
    return fn()
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G

-- Force a fresh normal EndHub boot. If a previous EndHub instance is still
-- alive, the normal work loader can legitimately return it without re-reading
-- config.json, which would make a newly seeded route look missing.
local live = ENV.ENDHUB
if live and live.Unload then
    pcall(function() live:Unload() end)
end
ENV.ENDHUB = nil
ENV.ENDHUB_BOOT = nil
ENV.ENDHUB_WORK_LOADING = nil

task.wait(0.15)

-- Seed the owner's 28-point route before the normal persistence module loads.
local seed = run("solara_normal_route_seed.lua")

-- Keep a lightweight visible-GUI click helper running for Solara. The normal
-- EndHub menu logic can use richer executor APIs when available, while this
-- helper provides ordinary mouse-click fallback for Endure/Play, Slot 1 and
-- Current Server on executors where those APIs are absent.
run("xs_menu_entry.lua")

-- Boot the full regular EndHub UI/features through the compatibility shim.
local hub = run("compat_loader.lua")

-- In-memory safety net: keep the exact same route table populated even if this
-- executor's filesystem behaves differently. The trinket route module captures
-- this table by reference, so mutating it here also updates the running module.
if type(hub) == "table" and type(seed) == "table" and type(seed.Route) == "table" then
    local placeKey = "125503525638054"
    hub.Config = hub.Config or {}
    hub.Config.TrinketRoutes = type(hub.Config.TrinketRoutes) == "table" and hub.Config.TrinketRoutes or {}
    local current = hub.Config.TrinketRoutes[placeKey]
    if type(current) ~= "table" then
        current = {}
        hub.Config.TrinketRoutes[placeKey] = current
    end
    table.clear(current)
    for i, point in ipairs(seed.Route) do
        current[i] = {point[1], point[2], point[3]}
    end
    hub.Config.TrinketExplore = true

    -- Refresh the visible dropdown when the UI is already built.
    local option = hub.UI and hub.UI.Options and hub.UI.Options.EH_TrinketRoutePoints
    if option and option.SetValues then
        local values = {}
        for i, p in ipairs(current) do
            values[#values + 1] = string.format("%d | %.1f, %.1f, %.1f", i, p[1], p[2], p[3])
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
