return function(H)
    if not H.UI or not H.UI.Window or not H.Boss then return end

    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}

    local Window = H.UI.Window
    local Options = H.UI.Options
    local Toggles = H.UI.Toggles
    local B = H.Boss

    local BossTab = Window:AddTab("Boss")
    H.UI.Tabs.Boss = BossTab

    local Left = BossTab:AddLeftGroupbox("Boss Farm")
    local Right = BossTab:AddRightGroupbox("Ranged / Position")
    local Status = BossTab:AddRightGroupbox("Status")

    local function targetValues()
        local values = B.GetNPCNames()
        local wanted = tostring(H.Config.BossTargetName or "AUTO: Highest MaxHealth")
        local found = false
        for _, v in ipairs(values) do if v == wanted then found = true break end end
        if not found and wanted ~= "" then values[#values + 1] = wanted end
        return values
    end

    local function weaponValues()
        local values = B.GetWeaponNames()
        local wanted = tostring(H.Config.BossWeaponName or "Use Equipped")
        local found = false
        for _, v in ipairs(values) do if v == wanted then found = true break end end
        if not found and wanted ~= "" then values[#values + 1] = wanted end
        return values
    end

    Left:AddToggle("EH_BossBot", {
        Text = "Automatic Boss Bot",
        Default = false,
        Callback = function(v)
            if v then B.Start() else B.Stop() end
        end,
    })

    Left:AddDropdown("EH_BossTarget", {
        Text = "Boss / NPC target",
        Values = targetValues(),
        Default = H.Config.BossTargetName,
        Multi = false,
        Searchable = true,
        Callback = function(v)
            if type(v) == "string" and v ~= "" then
                H.Config.BossTargetName = v
                B.Runtime.Target = nil
                B.Runtime.SafeDirection = nil
            end
        end,
    })

    Left:AddButton({Text = "Refresh Boss List", Func = function()
        if Options.EH_BossTarget then
            local values = targetValues()
            Options.EH_BossTarget:SetValues(values)
            if H.Config.BossTargetName then
                pcall(function() Options.EH_BossTarget:SetValue(H.Config.BossTargetName) end)
            end
        end
    end})

    Left:AddDropdown("EH_BossWeapon", {
        Text = "Ranged weapon",
        Values = weaponValues(),
        Default = H.Config.BossWeaponName,
        Multi = false,
        Searchable = true,
        Callback = function(v)
            if type(v) == "string" and v ~= "" then H.Config.BossWeaponName = v end
        end,
    })

    Left:AddButton({Text = "Refresh Weapon List", Func = function()
        if Options.EH_BossWeapon then
            local values = weaponValues()
            Options.EH_BossWeapon:SetValues(values)
            if H.Config.BossWeaponName then
                pcall(function() Options.EH_BossWeapon:SetValue(H.Config.BossWeaponName) end)
            end
        end
    end})

    Left:AddToggle("EH_BossAutoShoot", {
        Text = "Auto Shoot",
        Default = H.Config.BossAutoShoot,
        Callback = function(v) H.Config.BossAutoShoot = v end,
    })

    Left:AddToggle("EH_BossAim", {
        Text = "Lock Aim On Boss",
        Default = H.Config.BossLockAim,
        Callback = function(v) H.Config.BossLockAim = v end,
    })

    Left:AddToggle("EH_BossNoclip", {
        Text = "Boss Bot Noclip",
        Default = H.Config.BossNoclip,
        Callback = function(v) H.Config.BossNoclip = v end,
    })

    Left:AddButton({Text = "STOP BOSS BOT", Func = function()
        B.Stop()
        if Toggles.EH_BossBot then Toggles.EH_BossBot:SetValue(false) end
    end})

    Right:AddSlider("EH_BossRange", {
        Text = "Distance from boss",
        Default = H.Config.BossDistance,
        Min = 10, Max = 150, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.BossDistance = v end,
    })

    Right:AddSlider("EH_BossDepth", {
        Text = "Underground depth",
        Default = H.Config.BossDepth,
        Min = 0, Max = 60, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.BossDepth = v end,
    })

    Right:AddSlider("EH_BossShotInterval", {
        Text = "Shot interval",
        Default = H.Config.BossShotInterval,
        Min = 0.08, Max = 2.00, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.BossShotInterval = v end,
    })

    Right:AddDropdown("EH_BossAimPart", {
        Text = "Aim part",
        Values = {"Head", "Torso", "HumanoidRootPart"},
        Default = H.Config.BossAimPart,
        Multi = false,
        Callback = function(v) if type(v) == "string" then H.Config.BossAimPart = v end end,
    })

    Right:AddLabel("The bot keeps you at the selected distance and depth relative to the target, faces the target and aims the camera at it. If shots hit the map from too deep underground, reduce Underground depth.", true)
    Right:AddLabel("Weapon firing uses the equipped Tool / normal mouse activation path. Select your ranged weapon in the dropdown or leave Use Equipped.", true)

    Status:AddLabel("EH_BossStatus", {Text = "Status: IDLE", DoesWrap = true})
    Status:AddLabel("EH_BossTargetStatus", {Text = "Target: None", DoesWrap = true})
    Status:AddLabel("EH_BossHP", {Text = "HP: --/--", DoesWrap = true})
    Status:AddLabel("EH_BossWeaponStatus", {Text = "Weapon: None", DoesWrap = true})
    Status:AddLabel("EH_BossDistanceStatus", {Text = "Distance: --", DoesWrap = true})

    -- Editable boss keybind in the normal Keybinds page.
    local keyGroup = H.UI.KeyLeft or H.UI.KeyRight
    if keyGroup then
        local initial = ENV.ENDHUB_KEYBINDS.boss_toggle or "F2"
        keyGroup:AddLabel("Boss Bot"):AddKeyPicker("EH_KB_boss_toggle", {
            Default = initial,
            Mode = "Press",
            Text = "Boss Bot",
            NoUI = false,
            Callback = function(value)
                if H.State.Unloaded or value == false then return end
                if Toggles.EH_BossBot then
                    Toggles.EH_BossBot:SetValue(not Toggles.EH_BossBot.Value)
                else
                    B.Toggle()
                end
            end,
            ChangedCallback = function(newKey)
                local name = nil
                if type(newKey) == "string" then name = newKey
                elseif typeof(newKey) == "EnumItem" then name = newKey.Name end
                if name == "None" or name == "NONE" or name == "" then name = nil end
                ENV.ENDHUB_KEYBINDS.boss_toggle = name
                if H.Core and H.Core.SaveKeybinds then H.Core.SaveKeybinds() end
            end,
        })
    end

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                if Options.EH_BossStatus then Options.EH_BossStatus:SetText("Status: " .. tostring(H.State.BossStatus or "IDLE")) end
                if Options.EH_BossTargetStatus then Options.EH_BossTargetStatus:SetText("Target: " .. tostring(H.State.BossTarget or "None")) end
                if Options.EH_BossHP then Options.EH_BossHP:SetText("HP: " .. tostring(H.State.BossHP or "--/--")) end
                if Options.EH_BossWeaponStatus then Options.EH_BossWeaponStatus:SetText("Weapon: " .. tostring(H.State.BossWeapon or "None")) end
                if Options.EH_BossDistanceStatus then
                    local d = tonumber(H.State.BossDistance)
                    Options.EH_BossDistanceStatus:SetText(d and string.format("Distance: %.1f", d) or "Distance: --")
                end
            end)
            task.wait(0.2)
        end
    end)

    print("[EndHub] boss UI loaded")
end
