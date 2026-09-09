return function(root, pinnedRepo)
    assert(root and root.UI and root.State and not root.State.Unloaded, "Load EndHub first")

    local ctx = setmetatable({Connections = {}, Drawings = {}}, {__index = root})
    ctx.State = setmetatable({Unloaded = false}, {
        __index = root.State,
        __newindex = function(_, k, v) root.State[k] = v end,
    })
    ctx.Core = setmetatable({}, {__index = root.Core})
    function ctx.Core.Connect(signal, callback)
        local c = signal:Connect(callback)
        ctx.Connections[#ctx.Connections + 1] = c
        return c
    end
    function ctx:Unload() root:Unload() end

    local UI = root.UI
    local Tabs, Options, Toggles, Library = UI.Tabs, UI.Options, UI.Toggles, UI.Library
    ctx.UI = UI

    local features = {"Boss", "MobFarm", "PlayerTools", "Movement", "Visuals"}
    function ctx.CloseExtras()
        if ctx.State.Unloaded then return end
        ctx.State.Unloaded = true
        for _, key in ipairs({"BossBotEnabled", "MobFarmEnabled", "MovementFly",
            "MovementNoclip", "SpeedModifierEnabled", "PlayerESP", "NPCESP",
            "TrinketESP", "NoFog", "Fullbright"}) do
            ctx.Config[key] = false
        end
        for _, key in ipairs(features) do
            local feature = rawget(ctx, key)
            if feature then
                if feature.Stop then pcall(feature.Stop) end
                if feature.Reset then pcall(feature.Reset) end
                if root[key] == feature then root[key] = nil end
            end
        end
        for _, c in ipairs(ctx.Connections) do pcall(function() c:Disconnect() end) end
        for _, d in ipairs(ctx.Drawings) do pcall(function() d:Remove() end) end
        table.clear(ctx.Connections)
        table.clear(ctx.Drawings)
    end

    local function runSource(source, chunk)
        local fn, err = loadstring(source, chunk)
        assert(fn, err)
        local init = fn()
        assert(type(init) == "function", "invalid module " .. chunk)
        init(ctx)
    end

    local function loadPinned(name, hideUI)
        local oldUI = rawget(ctx, "UI")
        if hideUI then ctx.UI = false end
        local ok, err = pcall(function()
            runSource(game:HttpGet(pinnedRepo .. "/modules/" .. name .. ".lua"), "EndHub Extras " .. name)
        end)
        ctx.UI = oldUI or UI
        if not ok then error(err, 0) end
    end

    local function loadMain(path)
        runSource(game:HttpGet(root.Repo .. path .. "?v=" .. tostring(os.time()) .. "-" .. tostring(math.random(100000,999999))), "EndHub " .. path)
    end

    loadMain("modules/extras_movement.lua")
    loadPinned("players", true)
    loadPinned("visuals", true)
    loadPinned("boss", true)
    loadPinned("mob_farm", true)

    root.Movement = ctx.Movement
    root.PlayerTools = ctx.PlayerTools
    root.Visuals = ctx.Visuals
    root.Boss = ctx.Boss
    root.MobFarm = ctx.MobFarm

    ------------------------------------------------------------------------
    -- Movement
    ------------------------------------------------------------------------
    local moveLeft = Tabs.Movement:AddLeftGroupbox("Movement")
    local moveRight = Tabs.Movement:AddRightGroupbox("Settings")
    local quick = Tabs.Movement:AddRightGroupbox("Quick TP to Player")

    moveLeft:AddToggle("EH_Fly", {
        Text = "Fly", Default = false,
        Callback = function(v) ctx.Config.MovementFly = v end,
    })
    moveLeft:AddToggle("EH_Noclip", {
        Text = "Noclip", Default = false,
        Callback = function(v)
            ctx.Config.MovementNoclip = v
            if not v and not ctx.State.Running then ctx.Core.Noclip(false) end
        end,
    })
    moveLeft:AddToggle("EH_SpeedModifierEnabled", {
        Text = "Speed modifier", Default = false,
        Callback = function(v) ctx.Movement.SetSpeedModifier(v) end,
    })
    moveLeft:AddButton({Text = "Stop Fly", Func = function()
        ctx.Movement.StopFly()
        if Toggles.EH_Fly then Toggles.EH_Fly:SetValue(false) end
    end})
    moveLeft:AddButton({Text = "Reset Character", Func = function() ctx.Movement.ResetCharacter() end})

    moveRight:AddSlider("EH_FlySpeed", {
        Text = "Fly speed", Default = ctx.Config.MovementFlySpeed,
        Min = 20, Max = 400, Rounding = 0,
        Callback = function(v) ctx.Config.MovementFlySpeed = v end,
    })
    moveRight:AddSlider("EH_WalkSpeed", {
        Text = "Walk speed", Default = ctx.Config.WalkSpeed,
        Min = 16, Max = 100, Rounding = 0,
        Callback = function(v) ctx.Config.WalkSpeed = v end,
    })
    moveRight:AddSlider("EH_SpeedMultiplier", {
        Text = "Speed multiplier", Default = ctx.Config.SpeedMultiplier,
        Min = 1, Max = 5, Rounding = 1, Suffix = "x",
        Callback = function(v) ctx.Config.SpeedMultiplier = v end,
    })

    local function playerNames()
        local rows = ctx.PlayerTools.Names()
        if #rows == 0 then rows = {"None"} end
        return rows
    end
    quick:AddDropdown("EH_QuickTPPlayer", {
        Text = "Player", Values = playerNames(), Multi = false, Searchable = true,
        Callback = function(v)
            if v == "None" then ctx.PlayerTools.Select(nil) else ctx.PlayerTools.Select(v) end
        end,
    })
    quick:AddButton({Text = "Refresh Players", Func = function()
        local rows = playerNames()
        if Options.EH_QuickTPPlayer then Options.EH_QuickTPPlayer:SetValues(rows) end
        if Options.EH_PlayerSelect then Options.EH_PlayerSelect:SetValues(rows) end
    end})
    quick:AddButton({Text = "TP TO PLAYER", Func = function() ctx.PlayerTools.TeleportSelected() end})

    ------------------------------------------------------------------------
    -- Players
    ------------------------------------------------------------------------
    local playersLeft = Tabs.Players:AddLeftGroupbox("Player Selection")
    local playersRight = Tabs.Players:AddRightGroupbox("Selected Player")
    playersLeft:AddDropdown("EH_PlayerSelect", {
        Text = "Select player", Values = playerNames(), Multi = false, Searchable = true,
        Callback = function(v)
            if v == "None" then ctx.PlayerTools.Select(nil) else ctx.PlayerTools.Select(v) end
            if Options.EH_QuickTPPlayer then pcall(function() Options.EH_QuickTPPlayer:SetValue(v) end) end
        end,
    })
    playersLeft:AddButton({Text = "Refresh Players", Func = function()
        local rows = playerNames()
        if Options.EH_PlayerSelect then Options.EH_PlayerSelect:SetValues(rows) end
        if Options.EH_QuickTPPlayer then Options.EH_QuickTPPlayer:SetValues(rows) end
    end})
    playersLeft:AddButton({Text = "Teleport To Selected", Func = function() ctx.PlayerTools.TeleportSelected() end})
    playersLeft:AddButton({Text = "Spectate Selected", Func = function() ctx.PlayerTools.SpectateSelected() end})
    playersLeft:AddButton({Text = "Stop Spectate", Func = function() ctx.PlayerTools.StopSpectate() end})
    playersRight:AddLabel("EH_PlayerName", {Text = "Name: None"})
    playersRight:AddLabel("EH_PlayerRank", {Text = "Rank: N/A"})
    playersRight:AddLabel("EH_PlayerDistance", {Text = "Distance: --"})
    playersRight:AddLabel("EH_PlayerHealth", {Text = "HP: --"})
    playersRight:AddLabel("EH_PlayerEquipped", {Text = "Equipped: None", DoesWrap = true})
    playersRight:AddLabel("EH_SpectateStatus", {Text = "Spectating: OFF"})

    ------------------------------------------------------------------------
    -- Visual
    ------------------------------------------------------------------------
    local visualLeft = Tabs.Visuals:AddLeftGroupbox("ESP")
    local visualRight = Tabs.Visuals:AddRightGroupbox("Environment")
    visualLeft:AddToggle("EH_PlayerESP", {Text = "Player ESP", Default = false,
        Callback = function(v) ctx.Config.PlayerESP = v end})
    visualLeft:AddToggle("EH_NPCESP", {Text = "NPC ESP", Default = false,
        Callback = function(v) ctx.Config.NPCESP = v end})
    visualLeft:AddToggle("EH_ShowRank", {Text = "Show Rank", Default = ctx.Config.ESPShowRank,
        Callback = function(v) ctx.Config.ESPShowRank = v end})
    visualLeft:AddToggle("EH_ShowDistance", {Text = "Show Distance", Default = ctx.Config.ESPShowDistance,
        Callback = function(v) ctx.Config.ESPShowDistance = v end})
    visualLeft:AddToggle("EH_EquippedTags", {Text = "Equipped Tags", Default = ctx.Config.ESPShowEquipped,
        Callback = function(v) ctx.Config.ESPShowEquipped = v end})
    visualRight:AddToggle("EH_NoFog", {Text = "No Fog", Default = false,
        Callback = function(v) ctx.Config.NoFog = v end})
    visualRight:AddToggle("EH_Fullbright", {Text = "Fullbright", Default = false,
        Callback = function(v) ctx.Config.Fullbright = v end})
    visualRight:AddSlider("EH_Brightness", {Text = "Brightness", Default = ctx.Config.FullbrightBrightness,
        Min = 1, Max = 10, Rounding = 1, Callback = function(v) ctx.Config.FullbrightBrightness = v end})
    visualRight:AddSlider("EH_Ambient", {Text = "Ambient", Default = ctx.Config.FullbrightAmbient,
        Min = 0, Max = 1, Rounding = 2, Callback = function(v) ctx.Config.FullbrightAmbient = v end})
    visualRight:AddSlider("EH_ClockTime", {Text = "Clock time", Default = ctx.Config.FullbrightClockTime,
        Min = 0, Max = 24, Rounding = 1, Callback = function(v) ctx.Config.FullbrightClockTime = v end})

    loadMain("modules/extras_trinket_esp.lua")

    ------------------------------------------------------------------------
    -- Boss
    ------------------------------------------------------------------------
    local bossLeft = Tabs.Boss:AddLeftGroupbox("Boss Farm")
    local bossRight = Tabs.Boss:AddRightGroupbox("Position / Attack")
    local bossStatus = Tabs.Boss:AddRightGroupbox("Status")

    local function bossTargets()
        local rows = ctx.Boss.GetNPCNames()
        if #rows == 0 then rows = {"AUTO: Highest MaxHealth"} end
        return rows
    end
    local function bossWeapons()
        return ctx.Boss.GetWeaponNames()
    end
    bossLeft:AddToggle("EH_BossBot", {Text = "Automatic Boss Bot", Default = false,
        Callback = function(v) if v then ctx.Boss.Start() else ctx.Boss.Stop() end end})
    bossLeft:AddDropdown("EH_BossTarget", {Text = "Target", Values = bossTargets(),
        Default = ctx.Config.BossTargetName, Multi = false, Searchable = true,
        Callback = function(v) if type(v) == "string" then ctx.Config.BossTargetName = v ctx.Boss.Runtime.Target = nil end end})
    bossLeft:AddButton({Text = "Refresh Targets", Func = function()
        if Options.EH_BossTarget then Options.EH_BossTarget:SetValues(bossTargets()) end
    end})
    bossLeft:AddDropdown("EH_BossWeapon", {Text = "Weapon", Values = bossWeapons(),
        Default = ctx.Config.BossWeaponName, Multi = false, Searchable = true,
        Callback = function(v) if type(v) == "string" then ctx.Config.BossWeaponName = v end end})
    bossLeft:AddButton({Text = "Refresh Weapons", Func = function()
        if Options.EH_BossWeapon then Options.EH_BossWeapon:SetValues(bossWeapons()) end
    end})
    bossLeft:AddToggle("EH_BossAutoShoot", {Text = "Auto Shoot", Default = ctx.Config.BossAutoShoot,
        Callback = function(v) ctx.Config.BossAutoShoot = v end})
    bossLeft:AddToggle("EH_BossAim", {Text = "Lock Aim", Default = ctx.Config.BossLockAim,
        Callback = function(v) ctx.Config.BossLockAim = v end})
    bossLeft:AddToggle("EH_BossNoclip", {Text = "Noclip", Default = ctx.Config.BossNoclip,
        Callback = function(v) ctx.Config.BossNoclip = v end})
    bossLeft:AddButton({Text = "STOP BOSS BOT", Func = function()
        ctx.Boss.Stop()
        if Toggles.EH_BossBot then Toggles.EH_BossBot:SetValue(false) end
    end})
    bossRight:AddSlider("EH_BossRange", {Text = "Distance", Default = ctx.Config.BossDistance,
        Min = 10, Max = 150, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.BossDistance = v end})
    bossRight:AddSlider("EH_BossDepth", {Text = "Depth", Default = ctx.Config.BossDepth,
        Min = 0, Max = 60, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.BossDepth = v end})
    bossRight:AddSlider("EH_BossShotInterval", {Text = "Shot interval", Default = ctx.Config.BossShotInterval,
        Min = 0.08, Max = 2, Rounding = 2, Suffix = "s", Callback = function(v) ctx.Config.BossShotInterval = v end})
    bossRight:AddDropdown("EH_BossAimPart", {Text = "Aim part", Values = {"Head","Torso","HumanoidRootPart"},
        Default = ctx.Config.BossAimPart, Multi = false, Callback = function(v) if type(v) == "string" then ctx.Config.BossAimPart = v end end})
    bossStatus:AddLabel("EH_BossStatus", {Text = "Status: IDLE"})
    bossStatus:AddLabel("EH_BossTargetStatus", {Text = "Target: None"})
    bossStatus:AddLabel("EH_BossHP", {Text = "HP: --"})
    bossStatus:AddLabel("EH_BossDistanceStatus", {Text = "Distance: --"})
    bossStatus:AddLabel("EH_BossWeaponStatus", {Text = "Weapon: None"})

    ------------------------------------------------------------------------
    -- MobFarm
    ------------------------------------------------------------------------
    local mobLeft = Tabs.MobFarm:AddLeftGroupbox("Mob Farm")
    local mobRight = Tabs.MobFarm:AddRightGroupbox("Movement / Attack")
    local mobStatus = Tabs.MobFarm:AddRightGroupbox("Status")
    local function mobWeapons() return ctx.MobFarm.GetWeaponNames() end
    mobLeft:AddToggle("EH_MobFarmEnabled", {Text = "Automatic Mob Farm", Default = false,
        Callback = function(v) if v then ctx.MobFarm.Start() else ctx.MobFarm.Stop() end end})
    mobLeft:AddDropdown("EH_MobFarmWeapon", {Text = "Weapon", Values = mobWeapons(),
        Default = ctx.Config.MobFarmWeaponName, Multi = false, Searchable = true,
        Callback = function(v) if type(v) == "string" then ctx.Config.MobFarmWeaponName = v end end})
    mobLeft:AddButton({Text = "Refresh Weapons", Func = function()
        if Options.EH_MobFarmWeapon then Options.EH_MobFarmWeapon:SetValues(mobWeapons()) end
    end})
    mobLeft:AddSlider("EH_MobFarmDetectionRange", {Text = "Detection radius", Default = ctx.Config.MobFarmDetectionRange,
        Min = 50, Max = 3000, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.MobFarmDetectionRange = v ctx.MobFarm.Runtime.Target = nil end})
    mobLeft:AddButton({Text = "Scan Candidates", Func = function() ctx.MobFarm.Candidates(true) end})
    mobLeft:AddButton({Text = "STOP MOB FARM", Func = function()
        ctx.MobFarm.Stop()
        if Toggles.EH_MobFarmEnabled then Toggles.EH_MobFarmEnabled:SetValue(false) end
    end})
    mobRight:AddDropdown("EH_MobFarmMoveMode", {Text = "Movement", Values = {"Fly","TP"},
        Default = ctx.Config.MobFarmMoveMode, Multi = false,
        Callback = function(v) if v == "Fly" or v == "TP" then ctx.Config.MobFarmMoveMode = v end end})
    mobRight:AddSlider("EH_MobFarmDistance", {Text = "Range", Default = ctx.Config.MobFarmDistance,
        Min = 5, Max = 120, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.MobFarmDistance = v end})
    mobRight:AddSlider("EH_MobFarmSafetyMargin", {Text = "Safety margin", Default = ctx.Config.MobFarmSafetyMargin,
        Min = 2, Max = 40, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.MobFarmSafetyMargin = v end})
    mobRight:AddSlider("EH_MobFarmHeight", {Text = "Height", Default = ctx.Config.MobFarmHeight,
        Min = 0, Max = 40, Rounding = 0, Suffix = " studs", Callback = function(v) ctx.Config.MobFarmHeight = v end})
    mobRight:AddSlider("EH_MobFarmFlySpeed", {Text = "Fly speed", Default = ctx.Config.MobFarmFlySpeed,
        Min = 20, Max = 300, Rounding = 0, Callback = function(v) ctx.Config.MobFarmFlySpeed = v end})
    mobRight:AddSlider("EH_MobFarmShotInterval", {Text = "Shot interval", Default = ctx.Config.MobFarmShotInterval,
        Min = 0.08, Max = 2, Rounding = 2, Suffix = "s", Callback = function(v) ctx.Config.MobFarmShotInterval = v end})
    mobRight:AddSlider("EH_MobFarmOrbitSpeed", {Text = "Orbit speed", Default = ctx.Config.MobFarmOrbitSpeed,
        Min = 0, Max = 120, Rounding = 0, Callback = function(v) ctx.Config.MobFarmOrbitSpeed = v end})
    mobRight:AddToggle("EH_MobFarmLockAim", {Text = "Lock Aim", Default = ctx.Config.MobFarmLockAim,
        Callback = function(v) ctx.Config.MobFarmLockAim = v end})
    mobRight:AddToggle("EH_MobFarmNoclip", {Text = "Noclip", Default = ctx.Config.MobFarmNoclip,
        Callback = function(v) ctx.Config.MobFarmNoclip = v end})
    mobStatus:AddLabel("EH_MobFarmStatus", {Text = "Status: IDLE"})
    mobStatus:AddLabel("EH_MobFarmTarget", {Text = "Target: None"})
    mobStatus:AddLabel("EH_MobFarmHP", {Text = "HP: --"})
    mobStatus:AddLabel("EH_MobFarmCandidates", {Text = "Candidates: 0"})
    mobStatus:AddLabel("EH_MobFarmKills", {Text = "Kills: 0"})

    ------------------------------------------------------------------------
    -- Keybinds: every action starts unbound. Old F-key defaults are ignored.
    ------------------------------------------------------------------------
    local keyLeft = UI.KeyLeft or Tabs.Keybinds:AddLeftGroupbox("Keybinds")
    local keyRight = UI.KeyRight or Tabs.Keybinds:AddRightGroupbox("More Keybinds")
    UI.KeyLeft, UI.KeyRight = keyLeft, keyRight
    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local saved = ENV.ENDHUB_KEYBINDS
    local actions = {}

    local function keyName(key)
        if key == nil then return nil end
        if type(key) == "string" then return (key == "None" or key == "" or key == "NONE") and nil or key end
        if typeof(key) == "EnumItem" then return key.Name end
        return nil
    end
    local function addKey(group, id, text, fn)
        local sid = "clean_" .. id
        local optionId = "EH_KB2_" .. id
        local initial = saved[sid] or "None"
        local action = {Id = sid, OptionId = optionId, KeyName = keyName(initial)}
        actions[#actions + 1] = action
        group:AddLabel(text):AddKeyPicker(optionId, {
            Default = initial, Mode = "Press", Text = text, NoUI = false,
            Callback = function(value)
                if value == false or ctx.State.Unloaded or not ctx.Core.InputFocused() then return end
                task.spawn(fn)
            end,
            ChangedCallback = function(newKey)
                local name = keyName(newKey)
                if name then
                    for _, other in ipairs(actions) do
                        if other ~= action and other.KeyName == name then
                            other.KeyName = nil
                            saved[other.Id] = nil
                            if Options[other.OptionId] then pcall(function() Options[other.OptionId]:SetValue("None") end) end
                        end
                    end
                end
                action.KeyName = name
                saved[sid] = name
                if ctx.Core.SaveKeybinds then ctx.Core.SaveKeybinds() end
            end,
        })
    end
    local function flip(id, fallback)
        local t = Toggles[id]
        if t then t:SetValue(not t.Value) else fallback() end
    end

    addKey(keyLeft, "farm", "Trinket Bot", function() if root.State.Running then root.Farm.Stop() else root.Farm.Start() end end)
    addKey(keyLeft, "farm_sell", "Farm -> Full -> Sell", function() flip("EH_FarmSell", function() end) end)
    addKey(keyLeft, "fly", "Fly", function() flip("EH_Fly", function() ctx.Config.MovementFly = not ctx.Config.MovementFly end) end)
    addKey(keyLeft, "noclip", "Movement Noclip", function() flip("EH_Noclip", function() ctx.Config.MovementNoclip = not ctx.Config.MovementNoclip end) end)
    addKey(keyLeft, "reset_character", "Reset Character", function() ctx.Movement.ResetCharacter() end)
    addKey(keyLeft, "teleport_player", "Teleport Selected", function() ctx.PlayerTools.TeleportSelected() end)
    addKey(keyLeft, "boss", "Boss Bot", function() flip("EH_BossBot", function() ctx.Boss.Toggle() end) end)
    addKey(keyLeft, "mobfarm", "Mob Farm", function() flip("EH_MobFarmEnabled", function() ctx.MobFarm.Toggle() end) end)
    addKey(keyLeft, "show_ui", "Show / Hide UI", function() Library:Toggle() end)

    addKey(keyRight, "auto_sell", "Auto Sell", function() flip("EH_AutoSell", function() if root.Config.AutoSell then root.Sell.Stop() else root.Sell.Start() end end) end)
    addKey(keyRight, "player_esp", "Player ESP", function() flip("EH_PlayerESP", function() ctx.Config.PlayerESP = not ctx.Config.PlayerESP end) end)
    addKey(keyRight, "npc_esp", "NPC ESP", function() flip("EH_NPCESP", function() ctx.Config.NPCESP = not ctx.Config.NPCESP end) end)
    addKey(keyRight, "fullbright", "Fullbright", function() flip("EH_Fullbright", function() ctx.Config.Fullbright = not ctx.Config.Fullbright end) end)
    addKey(keyRight, "no_fog", "No Fog", function() flip("EH_NoFog", function() ctx.Config.NoFog = not ctx.Config.NoFog end) end)
    addKey(keyRight, "skip_target", "Skip Target", function() root.Farm.SkipTarget() end)
    addKey(keyRight, "reset_stats", "Reset Statistics", function() root.Farm.ResetStats() end)
    addKey(keyRight, "unload", "Unload Script", function() root:Unload() end)

    ------------------------------------------------------------------------
    -- Debug
    ------------------------------------------------------------------------
    local debugLeft = Tabs.Debug:AddLeftGroupbox("Debug")
    debugLeft:AddButton({Text = "Print Pause Diagnostic", Func = function()
        if root.ServerCycle and root.ServerCycle.Diagnostic then print("[EndHub Pause] " .. root.ServerCycle.Diagnostic()) end
    end})
    debugLeft:AddButton({Text = "Scan Mob Candidates", Func = function() ctx.MobFarm.Candidates(true) end})
    debugLeft:AddButton({Text = "Reset Farm Statistics", Func = function() root.Farm.ResetStats() end})

    task.spawn(function()
        while not ctx.State.Unloaded and not root.State.Unloaded do
            pcall(function()
                local info = ctx.PlayerTools.Info()
                if Options.EH_PlayerName then Options.EH_PlayerName:SetText("Name: " .. tostring(info.Name)) end
                if Options.EH_PlayerRank then Options.EH_PlayerRank:SetText("Rank: " .. tostring(info.Rank)) end
                if Options.EH_PlayerDistance then Options.EH_PlayerDistance:SetText("Distance: " .. (info.Distance and info.Distance ~= math.huge and tostring(math.floor(info.Distance)) or "--")) end
                if Options.EH_PlayerHealth then Options.EH_PlayerHealth:SetText("HP: " .. (info.Health and tostring(math.floor(info.Health)) or "--")) end
                if Options.EH_PlayerEquipped then Options.EH_PlayerEquipped:SetText("Equipped: " .. tostring(info.Equipped)) end
                if Options.EH_SpectateStatus then Options.EH_SpectateStatus:SetText("Spectating: " .. (ctx.PlayerTools.Spectating and "ON" or "OFF")) end

                if Options.EH_BossStatus then Options.EH_BossStatus:SetText("Status: " .. tostring(root.State.BossStatus or "IDLE")) end
                if Options.EH_BossTargetStatus then Options.EH_BossTargetStatus:SetText("Target: " .. tostring(root.State.BossTarget or "None")) end
                if Options.EH_BossHP then Options.EH_BossHP:SetText("HP: " .. tostring(root.State.BossHP or "--")) end
                if Options.EH_BossDistanceStatus then Options.EH_BossDistanceStatus:SetText("Distance: " .. string.format("%.1f", tonumber(root.State.BossDistance) or 0)) end
                if Options.EH_BossWeaponStatus then Options.EH_BossWeaponStatus:SetText("Weapon: " .. tostring(root.State.BossWeapon or "None")) end

                if Options.EH_MobFarmStatus then Options.EH_MobFarmStatus:SetText("Status: " .. tostring(root.State.MobFarmStatus or "IDLE")) end
                if Options.EH_MobFarmTarget then Options.EH_MobFarmTarget:SetText("Target: " .. tostring(root.State.MobFarmTarget or "None")) end
                if Options.EH_MobFarmHP then Options.EH_MobFarmHP:SetText("HP: " .. tostring(root.State.MobFarmHP or "--")) end
                if Options.EH_MobFarmCandidates then Options.EH_MobFarmCandidates:SetText("Candidates: " .. tostring(root.State.MobFarmCandidates or 0)) end
                if Options.EH_MobFarmKills then Options.EH_MobFarmKills:SetText("Kills: " .. tostring(root.State.MobFarmObservedKills or 0)) end
            end)
            task.wait(0.5)
        end
    end)

    print("[EndHub] unified extras loaded | single window | clean tabs | keybinds default OFF")
    return ctx
end
