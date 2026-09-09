return function(H)
    local Tabs = H.UI and H.UI.Tabs
    if not Tabs or not H.Movement or not H.PlayerTools then return end
    local Options, Toggles = H.UI.Options, H.UI.Toggles
    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local saved = ENV.ENDHUB_KEYBINDS

    local function keyName(key)
        if key == nil then return nil end
        if type(key) == "string" then
            if key == "None" or key == "NONE" or key == "" then return nil end
            return key
        end
        if typeof(key) == "EnumItem" then return key.Name end
        return nil
    end

    local function saveKey(id, key)
        saved[id] = keyName(key)
        if H.Core and H.Core.SaveKeybinds then H.Core.SaveKeybinds() end
    end

    ------------------------------------------------------------------------
    -- Movement
    ------------------------------------------------------------------------
    -- Fly toggle and its settings live in the same box.
    local flyGroup = Tabs.Movement:AddLeftGroupbox("Fly")
    local moveGroup = Tabs.Movement:AddRightGroupbox("Movement")

    local flyToggle = flyGroup:AddToggle("EH_Fly", {
        Text = "Fly", Default = false,
        Callback = function(v) H.Config.MovementFly = v end,
    })
    flyToggle:AddKeyPicker("EH_InlineFlyKey", {
        Default = saved.feature_fly or "None",
        Mode = "Press",
        Text = "Fly",
        NoUI = false,
        Callback = function(value)
            if value == false or H.State.Unloaded or not H.Core.InputFocused() then return end
            if Toggles.EH_Fly then Toggles.EH_Fly:SetValue(not Toggles.EH_Fly.Value) end
        end,
        ChangedCallback = function(newKey)
            saveKey("feature_fly", newKey)
        end,
    })

    flyGroup:AddSlider("EH_FlySpeed", {
        Text = "Fly speed", Default = H.Config.MovementFlySpeed,
        Min = 20, Max = 400, Rounding = 0,
        Callback = function(v) H.Config.MovementFlySpeed = v end,
    })
    flyGroup:AddButton({Text = "Stop Fly", Func = function()
        H.Movement.StopFly()
        if Toggles.EH_Fly then Toggles.EH_Fly:SetValue(false) end
    end})

    local noclipToggle = moveGroup:AddToggle("EH_Noclip", {
        Text = "Noclip", Default = false,
        Callback = function(v)
            H.Config.MovementNoclip = v
            if not v and not H.State.Running then H.Core.Noclip(false) end
        end,
    })
    noclipToggle:AddKeyPicker("EH_InlineNoclipKey", {
        Default = saved.feature_noclip or "None",
        Mode = "Press",
        Text = "Noclip",
        NoUI = false,
        Callback = function(value)
            if value == false or H.State.Unloaded or not H.Core.InputFocused() then return end
            if Toggles.EH_Noclip then Toggles.EH_Noclip:SetValue(not Toggles.EH_Noclip.Value) end
        end,
        ChangedCallback = function(newKey)
            saveKey("feature_noclip", newKey)
        end,
    })

    moveGroup:AddToggle("EH_SpeedModifierEnabled", {
        Text = "Speed modifier", Default = false,
        Callback = function(v) H.Movement.SetSpeedModifier(v) end,
    })
    moveGroup:AddSlider("EH_WalkSpeed", {
        Text = "Walk speed", Default = H.Config.WalkSpeed,
        Min = 16, Max = 100, Rounding = 0,
        Callback = function(v) H.Config.WalkSpeed = v end,
    })
    moveGroup:AddSlider("EH_SpeedMultiplier", {
        Text = "Speed multiplier", Default = H.Config.SpeedMultiplier,
        Min = 1, Max = 5, Rounding = 1, Suffix = "x",
        Callback = function(v) H.Config.SpeedMultiplier = v end,
    })

    ------------------------------------------------------------------------
    -- Players
    ------------------------------------------------------------------------
    local function playerNames()
        local rows = H.PlayerTools.Names()
        if #rows == 0 then rows = {"None"} end
        return rows
    end

    local playersLeft = Tabs.Players:AddLeftGroupbox("Player Selection")
    local playersRight = Tabs.Players:AddRightGroupbox("Selected Player")
    local actions = Tabs.Players:AddRightGroupbox("Player Actions")

    playersLeft:AddDropdown("EH_PlayerSelect", {
        Text = "Select player", Values = playerNames(), Multi = false, Searchable = true,
        Callback = function(v)
            if v == "None" then H.PlayerTools.Select(nil) else H.PlayerTools.Select(v) end
            if Options.EH_QuickTPPlayer then pcall(function() Options.EH_QuickTPPlayer:SetValue(v) end) end
        end,
    })
    playersLeft:AddButton({Text = "Refresh Players", Func = function()
        local rows = playerNames()
        if Options.EH_PlayerSelect then Options.EH_PlayerSelect:SetValues(rows) end
        if Options.EH_QuickTPPlayer then Options.EH_QuickTPPlayer:SetValues(rows) end
    end})
    playersLeft:AddButton({Text = "Teleport To Selected", Func = function() H.PlayerTools.TeleportSelected() end})
    playersLeft:AddButton({Text = "Spectate Selected", Func = function() H.PlayerTools.SpectateSelected() end})
    playersLeft:AddButton({Text = "Stop Spectate", Func = function() H.PlayerTools.StopSpectate() end})

    actions:AddDropdown("EH_QuickTPPlayer", {
        Text = "Quick TP to player", Values = playerNames(), Multi = false, Searchable = true,
        Callback = function(v)
            if v == "None" then H.PlayerTools.Select(nil) else H.PlayerTools.Select(v) end
            if Options.EH_PlayerSelect then pcall(function() Options.EH_PlayerSelect:SetValue(v) end) end
        end,
    })
    actions:AddButton({Text = "TP TO PLAYER", Func = function() H.PlayerTools.TeleportSelected() end})
    actions:AddButton({Text = "Reset Character", Func = function() H.Movement.ResetCharacter() end})

    playersRight:AddLabel("EH_PlayerName", {Text = "Name: None"})
    playersRight:AddLabel("EH_PlayerRank", {Text = "Rank: N/A"})
    playersRight:AddLabel("EH_PlayerDistance", {Text = "Distance: --"})
    playersRight:AddLabel("EH_PlayerHealth", {Text = "HP: --"})
    playersRight:AddLabel("EH_PlayerEquipped", {Text = "Equipped: None", DoesWrap = true})
    playersRight:AddLabel("EH_SpectateStatus", {Text = "Spectating: OFF"})

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                local info = H.PlayerTools.Info()
                if Options.EH_PlayerName then Options.EH_PlayerName:SetText("Name: " .. tostring(info.Name)) end
                if Options.EH_PlayerRank then Options.EH_PlayerRank:SetText("Rank: " .. tostring(info.Rank)) end
                if Options.EH_PlayerDistance then
                    Options.EH_PlayerDistance:SetText("Distance: " .. (info.Distance and info.Distance ~= math.huge and tostring(math.floor(info.Distance)) or "--"))
                end
                if Options.EH_PlayerHealth then Options.EH_PlayerHealth:SetText("HP: " .. (info.Health and tostring(math.floor(info.Health)) or "--")) end
                if Options.EH_PlayerEquipped then Options.EH_PlayerEquipped:SetText("Equipped: " .. tostring(info.Equipped)) end
                if Options.EH_SpectateStatus then Options.EH_SpectateStatus:SetText("Spectating: " .. (H.PlayerTools.Spectating and "ON" or "OFF")) end
            end)
            task.wait(0.5)
        end
    end)
end
