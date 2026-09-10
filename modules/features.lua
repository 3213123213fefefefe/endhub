return function(H)
    local F = {Loading = false, Context = nil, Generation = 0}
    H.Features = F
    F.PinnedRepo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/88cb7baf859ab6e44109be8258c98e43f35978d5"

    local function closeContext(ctx)
        if not ctx or ctx.State.Unloaded then return end
        ctx.State.Unloaded = true
        for _, key in ipairs({"BossBotEnabled", "MobFarmEnabled", "MovementFly",
            "MovementNoclip", "SpeedModifierEnabled", "PlayerESP", "NPCESP",
            "TrinketESP", "NoFog", "Fullbright"}) do
            ctx.Config[key] = false
        end
        for _, key in ipairs({"Boss", "MobFarm", "PlayerTools", "Movement", "Visuals"}) do
            local feature = rawget(ctx, key)
            if feature then
                if feature.Stop then pcall(feature.Stop) end
                if feature.Reset then pcall(feature.Reset) end
                if H[key] == feature then H[key] = nil end
            end
        end
        for _, c in ipairs(ctx.Connections) do pcall(function() c:Disconnect() end) end
        for _, d in ipairs(ctx.Drawings) do pcall(function() d:Remove() end) end
        table.clear(ctx.Connections)
        table.clear(ctx.Drawings)
    end

    function F.Close()
        F.Generation = F.Generation + 1
        local ctx = F.Context
        F.Context = nil
        closeContext(ctx)
    end

    local function makeContext()
        local ctx = setmetatable({Connections = {}, Drawings = {}}, {__index = H})
        ctx.State = setmetatable({Unloaded = false}, {
            __index = H.State,
            __newindex = function(_, k, v) H.State[k] = v end,
        })
        ctx.Core = setmetatable({}, {__index = H.Core})
        function ctx.Core.Connect(signal, callback)
            local c = signal:Connect(callback)
            ctx.Connections[#ctx.Connections + 1] = c
            return c
        end
        function ctx:Unload() H:Unload() end
        ctx.UI = H.UI
        return ctx
    end

    local function runSource(ctx, source, chunk)
        local fn, err = loadstring(source, chunk)
        assert(fn, err)
        local init = fn()
        assert(type(init) == "function", "invalid module " .. chunk)
        init(ctx)
    end

    local function loadPinned(ctx, name, hideUI)
        local oldUI = rawget(ctx, "UI")
        if hideUI then ctx.UI = false end
        local ok, err = pcall(function()
            runSource(ctx, game:HttpGet(F.PinnedRepo .. "/modules/" .. name .. ".lua"), "EndHub Feature " .. name)
        end)
        ctx.UI = oldUI or H.UI
        if not ok then error(err, 0) end
    end

    local function loadMain(ctx, path)
        local source = game:HttpGet(H.Repo .. path .. "?v=" .. tostring(os.time()) .. "-" .. tostring(math.random(100000,999999)))
        runSource(ctx, source, "EndHub " .. path)
    end

    function F.Load()
        if F.Loading or H.State.Unloaded then return false end
        if F.Context and not F.Context.State.Unloaded then return true end
        F.Loading = true
        local generation = F.Generation

        task.spawn(function()
            local ctx = makeContext()
            local ok, err = pcall(function()
                loadMain(ctx, "modules/extras_movement.lua")
                loadPinned(ctx, "players", true)
                loadMain(ctx, "modules/visuals.lua")
                loadPinned(ctx, "boss", true)
                loadPinned(ctx, "mob_farm", true)

                H.Movement = ctx.Movement
                H.PlayerTools = ctx.PlayerTools
                H.Visuals = ctx.Visuals
                H.Boss = ctx.Boss
                H.MobFarm = ctx.MobFarm

                loadMain(ctx, "modules/features_player_movement_ui.lua")
                loadMain(ctx, "modules/features_visual_ui.lua")
                loadMain(ctx, "modules/extras_trinket_esp.lua")
                loadMain(ctx, "modules/features_combat_ui.lua")
                loadMain(ctx, "modules/features_keybind_ui.lua")
            end)

            if H.State.Unloaded or generation ~= F.Generation then
                closeContext(ctx)
                F.Loading = false
                return
            end

            if not ok then
                closeContext(ctx)
                warn("[EndHub Features] " .. tostring(err))
            else
                F.Context = ctx
                print("[EndHub] features loaded | Movement + Players + Visual + Boss + MobFarm + Keybinds")
            end
            F.Loading = false
        end)
        return true
    end
end
