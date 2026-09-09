-- Optional tools use the existing farm/sale controller, never another bot.
return function(root, repo)
    assert(root and root.State and not root.State.Unloaded, "Load EndHub first")
    local ctx = setmetatable({Connections = {}, Drawings = {}}, {__index = root})
    ctx.State = setmetatable({Unloaded = false}, {
        __index = root.State, __newindex = function(_, k, v) root.State[k] = v end,
    })
    ctx.Core = setmetatable({}, {__index = root.Core})
    function ctx.Core.Connect(signal, callback)
        local c = signal:Connect(callback)
        ctx.Connections[#ctx.Connections + 1] = c
        return c
    end
    function ctx:Unload() root:Unload() end
    local features = {"Boss", "MobFarm", "NoKillbrick", "PlayerTools", "Movement", "Visuals", "Legacy"}
    function ctx.CloseExtras()
        if ctx.State.Unloaded then return end
        ctx.State.Unloaded = true
        for _, key in ipairs({"BossBotEnabled", "MobFarmEnabled", "NoKillbrick", "MovementFly",
            "MovementNoclip", "SpeedModifierEnabled", "Desync", "PlayerESP", "NPCESP",
            "TrinketESP", "NoFog", "Fullbright"}) do ctx.Config[key] = false end
        for _, key in ipairs(features) do
            local feature = rawget(ctx, key)
            if feature then
                if feature.Stop then pcall(feature.Stop) end
                if feature.Reset then pcall(feature.Reset) end
                if root[key] == feature then root[key] = nil end
            end
        end
        local ui = rawget(ctx, "UI")
        if ui and ui.Library then pcall(function() ui.Library:Unload() end) end
        for _, c in ipairs(ctx.Connections) do pcall(function() c:Disconnect() end) end
        for _, d in ipairs(ctx.Drawings) do pcall(function() d:Remove() end) end
        table.clear(ctx.Connections)
        table.clear(ctx.Drawings)
        -- Library stores a convenience global; restore the still-live main UI.
        if not root.State.Unloaded then getgenv().Library = root.UI.Library end
    end
    local ok, err = pcall(function()
        for _, name in ipairs({"movement", "boss", "players", "visuals", "ui", "speed_ui",
            "no_killbrick", "seller_tools", "legacy_features", "keybinds", "boss_ui",
            "mob_farm", "boss_detection", "trinket_esp", "sell_diagnostics", "persistence_ui", "farm_tuning", "logger_ui"}) do
            if root.State.Unloaded then error("EndHub unloaded during Extras download") end
            local source = game:HttpGet(repo .. "/modules/" .. name .. ".lua")
            if root.State.Unloaded then error("EndHub unloaded during Extras download") end
            local fn, compileError = loadstring(source, "EndHub Extras " .. name)
            assert(fn, compileError)
            fn()(ctx)
        end
        for _, name in ipairs(features) do root[name] = rawget(ctx, name) end
    end)
    if not ok then ctx.CloseExtras() error(err, 0) end
    return ctx
end
