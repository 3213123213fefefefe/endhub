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

    local statusLabels = {}
    local function addStatus(id, text)
        statusLabels[id] = Status:AddLabel(id, {Text = text, DoesWrap = true})
    end
    addStatus("EH_BossStatus", "Status: IDLE")
    addStatus("EH_BossSelectedStatus", "Selected: None")
    addStatus("EH_BossTargetStatus", "Detected target: None")
    addStatus("EH_BossHP", "HP: --")
    addStatus("EH_BossDistanceStatus", "Current distance: --")
    addStatus("EH_BossDetectionStatus", "Detection radius: --")
    addStatus("EH_BossPositionStatus", "Desired distance / depth: --")
    addStatus("EH_BossWeaponStatus", "Equipped: None")
    addStatus("EH_BossWeaponSelected", "Selected weapon: --")
    addStatus("EH_BossFireStatus", "Auto shoot: OFF")
    local function setStatus(id, text)
        local label = statusLabels[id]
        if not label or type(label.SetText) ~= "function" then label = Options[id] end
        if label and type(label.SetText) == "function" then label:SetText(text) end
    end

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
        local reported = false
        while not H.State.Unloaded do
            local ok, err = pcall(function()
                local enabled = H.Config.BossBotEnabled == true
                local target = enabled and B.Runtime.Target or nil
                local hum = target and target.Parent and target:FindFirstChildWhichIsA("Humanoid")
                local root = H.Core.Root()
                local part = hum and H.Core.NPCAnchor(target)
                local valid = hum and hum.Health > 0 and part
                local wanted = tostring(H.Config.BossTargetName or "None")
                local selectedName = wanted:match("^(.-) | ") or wanted
                local selected = wanted ~= "SELECT A BOSS / NPC" and wanted ~= "AUTO: Highest MaxHealth" and wanted ~= "None"
                local status
                if not enabled then status = selected and "STOPPED" or "SELECT A TARGET"
                elseif not root then status = "WAITING FOR CHARACTER"
                elseif not valid then status = "WAITING: TARGET NOT FOUND IN DETECTION RADIUS"
                else status = tostring(H.State.BossStatus or "READY") end
                setStatus("EH_BossStatus", "Status: " .. status)
                setStatus("EH_BossSelectedStatus", "Selected: " .. (selected and selectedName or "None"))
                setStatus("EH_BossTargetStatus", "Detected target: " .. (valid and target.Name or "None"))
                local hp = "--"
                if valid then
                    local max = math.max(0, hum.MaxHealth)
                    local percent = max > 0 and math.clamp(hum.Health / max * 100, 0, 100) or 0
                    hp = string.format("%.0f / %.0f (%.1f%%)", math.max(0, hum.Health), max, percent)
                end
                setStatus("EH_BossHP", "HP: " .. hp)
                local distance = valid and root and (root.Position - part.Position).Magnitude
                setStatus("EH_BossDistanceStatus", "Current distance: " .. (distance and string.format("%.1f studs", distance) or "--"))
                setStatus("EH_BossDetectionStatus", "Detection radius: " .. tostring(H.Config.BossDetectionRange or 500) .. " studs")
                setStatus("EH_BossPositionStatus", string.format("Desired distance: %.0f | Depth: %.0f studs", H.Config.BossDistance or 55, H.Config.BossDepth or 0))
                local character = H.Core.Character()
                local equipped = character and character:FindFirstChildWhichIsA("Tool")
                setStatus("EH_BossWeaponStatus", "Equipped: " .. (equipped and equipped.Name or "None"))
                setStatus("EH_BossWeaponSelected", "Selected weapon: " .. tostring(H.Config.BossWeaponName or "Use Equipped"))
                setStatus("EH_BossFireStatus", "Auto shoot: " .. (H.Config.BossAutoShoot and "ON" or "OFF")
                    .. string.format(" | Interval: %.2fs", H.Config.BossShotInterval or 0.45))
            end)
            if not ok and not reported then warn("[EndHub Boss UI] " .. tostring(err)) end
            reported = not ok
            task.wait(0.2)
        end
    end)

    print("[EndHub] boss UI loaded")
end

