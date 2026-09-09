return function(H)
    local Tabs = H.UI and H.UI.Tabs
    if not Tabs or not H.Boss or not H.MobFarm then return end
    local Options, Toggles = H.UI.Options, H.UI.Toggles

    ------------------------------------------------------------------------
    -- Boss
    ------------------------------------------------------------------------
    local bossLeft = Tabs.Boss:AddLeftGroupbox("Boss Farm")
    local bossRight = Tabs.Boss:AddRightGroupbox("Position / Attack")
    local bossStatus = Tabs.Boss:AddRightGroupbox("Status")

    local function bossTargets()
        local rows = H.Boss.GetNPCNames()
        if #rows == 0 then rows = {"AUTO: Highest MaxHealth"} end
        return rows
    end

    local function bossWeapons()
        return H.Boss.GetWeaponNames()
    end

    bossLeft:AddToggle("EH_BossBot", {
        Text = "Automatic Boss Bot", Default = false,
        Callback = function(v) if v then H.Boss.Start() else H.Boss.Stop() end end,
    })
    bossLeft:AddDropdown("EH_BossTarget", {
        Text = "Target", Values = bossTargets(), Default = H.Config.BossTargetName,
        Multi = false, Searchable = true,
        Callback = function(v)
            if type(v) == "string" then
                H.Config.BossTargetName = v
                H.Boss.Runtime.Target = nil
            end
        end,
    })
    bossLeft:AddButton({Text = "Refresh Targets", Func = function()
        if Options.EH_BossTarget then Options.EH_BossTarget:SetValues(bossTargets()) end
    end})
    bossLeft:AddDropdown("EH_BossWeapon", {
        Text = "Weapon", Values = bossWeapons(), Default = H.Config.BossWeaponName,
        Multi = false, Searchable = true,
        Callback = function(v) if type(v) == "string" then H.Config.BossWeaponName = v end end,
    })
    bossLeft:AddButton({Text = "Refresh Weapons", Func = function()
        if Options.EH_BossWeapon then Options.EH_BossWeapon:SetValues(bossWeapons()) end
    end})
    bossLeft:AddToggle("EH_BossAutoShoot", {
        Text = "Auto Shoot", Default = H.Config.BossAutoShoot,
        Callback = function(v) H.Config.BossAutoShoot = v end,
    })
    bossLeft:AddToggle("EH_BossAim", {
        Text = "Lock Aim", Default = H.Config.BossLockAim,
        Callback = function(v) H.Config.BossLockAim = v end,
    })
    bossLeft:AddToggle("EH_BossNoclip", {
        Text = "Noclip", Default = H.Config.BossNoclip,
        Callback = function(v) H.Config.BossNoclip = v end,
    })
    bossLeft:AddButton({Text = "STOP BOSS BOT", Func = function()
        H.Boss.Stop()
        if Toggles.EH_BossBot then Toggles.EH_BossBot:SetValue(false) end
    end})

    bossRight:AddSlider("EH_BossRange", {
        Text = "Distance", Default = H.Config.BossDistance,
        Min = 10, Max = 150, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.BossDistance = v end,
    })
    bossRight:AddSlider("EH_BossDepth", {
        Text = "Depth", Default = H.Config.BossDepth,
        Min = 0, Max = 60, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.BossDepth = v end,
    })
    bossRight:AddSlider("EH_BossShotInterval", {
        Text = "Shot interval", Default = H.Config.BossShotInterval,
        Min = 0.08, Max = 2, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.BossShotInterval = v end,
    })
    bossRight:AddDropdown("EH_BossAimPart", {
        Text = "Aim part", Values = {"Head", "Torso", "HumanoidRootPart"},
        Default = H.Config.BossAimPart, Multi = false,
        Callback = function(v) if type(v) == "string" then H.Config.BossAimPart = v end end,
    })

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

    local function mobWeapons()
        return H.MobFarm.GetWeaponNames()
    end

    mobLeft:AddToggle("EH_MobFarmEnabled", {
        Text = "Automatic Mob Farm", Default = false,
        Callback = function(v) if v then H.MobFarm.Start() else H.MobFarm.Stop() end end,
    })
    mobLeft:AddDropdown("EH_MobFarmWeapon", {
        Text = "Weapon", Values = mobWeapons(), Default = H.Config.MobFarmWeaponName,
        Multi = false, Searchable = true,
        Callback = function(v) if type(v) == "string" then H.Config.MobFarmWeaponName = v end end,
    })
    mobLeft:AddButton({Text = "Refresh Weapons", Func = function()
        if Options.EH_MobFarmWeapon then Options.EH_MobFarmWeapon:SetValues(mobWeapons()) end
    end})
    mobLeft:AddSlider("EH_MobFarmDetectionRange", {
        Text = "Detection radius", Default = H.Config.MobFarmDetectionRange,
        Min = 50, Max = 3000, Rounding = 0, Suffix = " studs",
        Callback = function(v)
            H.Config.MobFarmDetectionRange = v
            H.MobFarm.Runtime.Target = nil
        end,
    })
    mobLeft:AddButton({Text = "Scan Candidates", Func = function() H.MobFarm.Candidates(true) end})
    mobLeft:AddButton({Text = "STOP MOB FARM", Func = function()
        H.MobFarm.Stop()
        if Toggles.EH_MobFarmEnabled then Toggles.EH_MobFarmEnabled:SetValue(false) end
    end})

    mobRight:AddDropdown("EH_MobFarmMoveMode", {
        Text = "Movement", Values = {"Fly", "TP"}, Default = H.Config.MobFarmMoveMode,
        Multi = false,
        Callback = function(v) if v == "Fly" or v == "TP" then H.Config.MobFarmMoveMode = v end end,
    })
    mobRight:AddSlider("EH_MobFarmDistance", {
        Text = "Range", Default = H.Config.MobFarmDistance,
        Min = 5, Max = 120, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.MobFarmDistance = v end,
    })
    mobRight:AddSlider("EH_MobFarmSafetyMargin", {
        Text = "Safety margin", Default = H.Config.MobFarmSafetyMargin,
        Min = 2, Max = 40, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.MobFarmSafetyMargin = v end,
    })
    mobRight:AddSlider("EH_MobFarmHeight", {
        Text = "Height", Default = H.Config.MobFarmHeight,
        Min = 0, Max = 40, Rounding = 0, Suffix = " studs",
        Callback = function(v) H.Config.MobFarmHeight = v end,
    })
    mobRight:AddSlider("EH_MobFarmFlySpeed", {
        Text = "Fly speed", Default = H.Config.MobFarmFlySpeed,
        Min = 20, Max = 300, Rounding = 0,
        Callback = function(v) H.Config.MobFarmFlySpeed = v end,
    })
    mobRight:AddSlider("EH_MobFarmShotInterval", {
        Text = "Shot interval", Default = H.Config.MobFarmShotInterval,
        Min = 0.08, Max = 2, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.MobFarmShotInterval = v end,
    })
    mobRight:AddSlider("EH_MobFarmOrbitSpeed", {
        Text = "Orbit speed", Default = H.Config.MobFarmOrbitSpeed,
        Min = 0, Max = 120, Rounding = 0,
        Callback = function(v) H.Config.MobFarmOrbitSpeed = v end,
    })
    mobRight:AddToggle("EH_MobFarmLockAim", {
        Text = "Lock Aim", Default = H.Config.MobFarmLockAim,
        Callback = function(v) H.Config.MobFarmLockAim = v end,
    })
    mobRight:AddToggle("EH_MobFarmNoclip", {
        Text = "Noclip", Default = H.Config.MobFarmNoclip,
        Callback = function(v) H.Config.MobFarmNoclip = v end,
    })

    mobStatus:AddLabel("EH_MobFarmStatus", {Text = "Status: IDLE"})
    mobStatus:AddLabel("EH_MobFarmTarget", {Text = "Target: None"})
    mobStatus:AddLabel("EH_MobFarmHP", {Text = "HP: --"})
    mobStatus:AddLabel("EH_MobFarmCandidates", {Text = "Candidates: 0"})
    mobStatus:AddLabel("EH_MobFarmKills", {Text = "Kills: 0"})

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                if Options.EH_BossStatus then Options.EH_BossStatus:SetText("Status: " .. tostring(H.State.BossStatus or "IDLE")) end
                if Options.EH_BossTargetStatus then Options.EH_BossTargetStatus:SetText("Target: " .. tostring(H.State.BossTarget or "None")) end
                if Options.EH_BossHP then Options.EH_BossHP:SetText("HP: " .. tostring(H.State.BossHP or "--")) end
                if Options.EH_BossDistanceStatus then Options.EH_BossDistanceStatus:SetText("Distance: " .. string.format("%.1f", tonumber(H.State.BossDistance) or 0)) end
                if Options.EH_BossWeaponStatus then Options.EH_BossWeaponStatus:SetText("Weapon: " .. tostring(H.State.BossWeapon or "None")) end

                if Options.EH_MobFarmStatus then Options.EH_MobFarmStatus:SetText("Status: " .. tostring(H.State.MobFarmStatus or "IDLE")) end
                if Options.EH_MobFarmTarget then Options.EH_MobFarmTarget:SetText("Target: " .. tostring(H.State.MobFarmTarget or "None")) end
                if Options.EH_MobFarmHP then Options.EH_MobFarmHP:SetText("HP: " .. tostring(H.State.MobFarmHP or "--")) end
                if Options.EH_MobFarmCandidates then Options.EH_MobFarmCandidates:SetText("Candidates: " .. tostring(H.State.MobFarmCandidates or 0)) end
                if Options.EH_MobFarmKills then Options.EH_MobFarmKills:SetText("Kills: " .. tostring(H.State.MobFarmObservedKills or 0)) end
            end)
            task.wait(0.5)
        end
    end)
end
