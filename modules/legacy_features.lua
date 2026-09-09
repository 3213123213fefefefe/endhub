return function(H)
    H.Legacy = {}
    local L = H.Legacy
    local C = H.Core
    local Players = H.S.Players
    local Lighting = H.S.Lighting
    local LocalPlayer = H.S.Player

    local UI = H.UI
    local Tabs = UI and UI.Tabs
    local Options = UI and UI.Options
    local Toggles = UI and UI.Toggles

    local equipped = {}
    local glareBackup = {}
    local lastNoFog = false

    L.Scan = {
        TotalStacks = 0,
        TotalItems = 0,
        MatchingItems = 0,
        MatchingStacks = 0,
        RarityCounts = {},
        CategoryCounts = {},
        TrinketDebug = {},
        DetectedRarities = {},
    }

    local function toggleValue(id, value, fallback)
        local t = Toggles and Toggles[id]
        if t and t.SetValue then
            t:SetValue(value)
        elseif fallback then
            fallback(value)
        end
    end

    local function removeEquipped(plr)
        local entry = equipped[plr]
        if entry then
            pcall(function() entry.Gui:Destroy() end)
            equipped[plr] = nil
        end
    end

    local function ensureEquipped(plr)
        if plr == LocalPlayer then return nil end
        local ch = plr.Character
        local head = ch and ch:FindFirstChild("Head")
        if not head then
            removeEquipped(plr)
            return nil
        end

        local entry = equipped[plr]
        if entry and entry.Gui and entry.Gui.Parent == head then
            return entry
        end

        removeEquipped(plr)

        local bb = Instance.new("BillboardGui")
        bb.Name = "EndHub_Equipped"
        bb.Size = UDim2.new(0, 260, 0, 24)
        bb.StudsOffset = Vector3.new(0, 5.2, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 2500
        bb.Parent = head

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 14
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.35
        label.Text = "Equipped: None"
        label.Parent = bb

        entry = {Gui = bb, Label = label}
        equipped[plr] = entry
        return entry
    end

    function L.UpdateEquipped()
        if not H.Config.ESPShowEquipped then
            for plr in pairs(equipped) do removeEquipped(plr) end
            return
        end

        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                seen[plr] = true
                local entry = ensureEquipped(plr)
                if entry then
                    local tool = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
                    entry.Label.Text = tool and ("Equipped: " .. tool.Name) or "Equipped: None"
                end
            end
        end

        for plr in pairs(equipped) do
            if not seen[plr] then removeEquipped(plr) end
        end
    end

    local function rememberGlare(atmosphere)
        if atmosphere and atmosphere:IsA("Atmosphere") and glareBackup[atmosphere] == nil then
            glareBackup[atmosphere] = atmosphere.Glare
        end
    end

    local function applyNoFogGlare()
        for _, obj in ipairs(Lighting:GetDescendants()) do
            if obj:IsA("Atmosphere") then
                rememberGlare(obj)
                obj.Glare = 0
            end
        end
    end

    local function restoreNoFogGlare()
        for obj, value in pairs(glareBackup) do
            if obj and obj.Parent then
                pcall(function() obj.Glare = value end)
            end
        end
        table.clear(glareBackup)
    end

    function L.ScanInventory()
        local scan = {
            TotalStacks = 0,
            TotalItems = 0,
            MatchingItems = 0,
            MatchingStacks = 0,
            RarityCounts = {},
            CategoryCounts = {},
            TrinketDebug = {},
            DetectedRarities = {},
        }

        local seenRarities = {}
        local entries = H.Sell.InventoryEntries()
        for _, entry in ipairs(entries) do
            scan.TotalStacks = scan.TotalStacks + 1
            scan.TotalItems = scan.TotalItems + math.max(1, entry.Amount or 1)

            local rarity = C.NormalizeRarity(entry.Rarity)
            local category = entry.Category or "Unknown"
            scan.CategoryCounts[category] = (scan.CategoryCounts[category] or 0) + 1
            scan.RarityCounts[rarity] = (scan.RarityCounts[rarity] or 0) + 1

            if not seenRarities[rarity] then
                seenRarities[rarity] = true
                scan.DetectedRarities[#scan.DetectedRarities + 1] = rarity
            end

            if category == "Trinket" then
                scan.TrinketDebug[#scan.TrinketDebug + 1] =
                    tostring(entry.Tool and entry.Tool.Name or "?") .. "=" .. rarity .. "x" .. tostring(entry.Amount or 1)
            end
        end

        table.sort(scan.DetectedRarities)
        table.sort(scan.TrinketDebug)

        local payload, stacks = H.Sell.BuildPayload()
        scan.MatchingItems = #payload
        scan.MatchingStacks = stacks or 0

        L.Scan = scan
        H.Sell.Runtime.RarityCounts = scan.RarityCounts
        H.Sell.Runtime.TrinketDebug = scan.TrinketDebug
        H.State.SellStatus = "INVENTORY SCANNED"
        return scan
    end

    local function rarityText()
        if #L.Scan.DetectedRarities == 0 then return "Detected rarities: --" end
        return "Detected rarities: " .. table.concat(L.Scan.DetectedRarities, ", ")
    end

    local function trinketText()
        local parts = {}
        for rarity, count in pairs(L.Scan.RarityCounts or {}) do
            parts[#parts + 1] = tostring(rarity) .. "=" .. tostring(count)
        end
        table.sort(parts)
        return #parts > 0 and ("Rarity stacks: " .. table.concat(parts, ", ")) or "Rarity stacks: --"
    end

    if Tabs then
        local SellDiag = Tabs.Sell:AddRightGroupbox("Inventory Diagnostics")
        SellDiag:AddButton({Text = "SCAN INVENTORY", Func = function() L.ScanInventory() end})
        SellDiag:AddLabel("EH_LegacyScanTotal", {Text = "Inventory: --", DoesWrap = true})
        SellDiag:AddLabel("EH_LegacyScanMatch", {Text = "Matching: --", DoesWrap = true})
        SellDiag:AddLabel("EH_LegacyScanRarities", {Text = "Detected rarities: --", DoesWrap = true})
        SellDiag:AddLabel("EH_LegacyScanTrinkets", {Text = "Trinkets: --", DoesWrap = true})

        local VisualQuick = Tabs.Visuals:AddLeftGroupbox("Quick ESP Controls")
        VisualQuick:AddButton({Text = "ESP All", Func = function()
            toggleValue("EH_PlayerESP", true, function(v) H.Config.PlayerESP = v end)
            toggleValue("EH_ShowRank", true, function(v) H.Config.ESPShowRank = v end)
            toggleValue("EH_ShowDistance", true, function(v) H.Config.ESPShowDistance = v end)
        end})
        VisualQuick:AddButton({Text = "ESP Off", Func = function()
            toggleValue("EH_PlayerESP", false, function(v) H.Config.PlayerESP = v end)
        end})
        VisualQuick:AddButton({Text = "Equipped All", Func = function()
            toggleValue("EH_EquippedTags", true, function(v) H.Config.ESPShowEquipped = v end)
        end})
        VisualQuick:AddLabel("EH_LegacyVisualSelected", {Text = "Selected: None"})
        VisualQuick:AddLabel("EH_LegacyVisualDistance", {Text = "Distance: --"})
        VisualQuick:AddLabel("EH_LegacyVisualHealth", {Text = "HP: --"})
        VisualQuick:AddLabel("EH_LegacyVisualRank", {Text = "Rank: N/A"})

        local MoveQuick = Tabs.Movement:AddRightGroupbox("Selected Player Quick Actions")
        MoveQuick:AddLabel("EH_LegacyMoveSelected", {Text = "Selected: None"})
        MoveQuick:AddButton({Text = "Teleport To Selected", Func = function() H.PlayerTools.TeleportSelected() end})
        MoveQuick:AddButton({Text = "Spectate Selected", Func = function() H.PlayerTools.SpectateSelected() end})
        MoveQuick:AddButton({Text = "Stop Spectate", Func = function() H.PlayerTools.StopSpectate() end})
        MoveQuick:AddLabel("WASD = Move")
        MoveQuick:AddLabel("Space = Up")
        MoveQuick:AddLabel("Ctrl = Down")
    end

    C.Connect(Lighting.DescendantAdded, function(obj)
        if obj:IsA("Atmosphere") then
            rememberGlare(obj)
            if H.Config.NoFog then task.defer(function() if obj.Parent then obj.Glare = 0 end end) end
        end
    end)

    C.Connect(Players.PlayerRemoving, function(plr)
        removeEquipped(plr)
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                L.UpdateEquipped()

                if H.Config.NoFog then
                    applyNoFogGlare()
                    lastNoFog = true
                elseif lastNoFog then
                    restoreNoFogGlare()
                    lastNoFog = false
                end

                if Options then
                    local scan = L.Scan
                    if Options.EH_LegacyScanTotal then
                        Options.EH_LegacyScanTotal:SetText("Inventory: " .. tostring(scan.TotalItems) .. " items / " .. tostring(scan.TotalStacks) .. " stacks")
                    end
                    if Options.EH_LegacyScanMatch then
                        Options.EH_LegacyScanMatch:SetText("Matching: " .. tostring(scan.MatchingItems) .. " items / " .. tostring(scan.MatchingStacks) .. " stacks")
                    end
                    if Options.EH_LegacyScanRarities then Options.EH_LegacyScanRarities:SetText(rarityText()) end
                    if Options.EH_LegacyScanTrinkets then
                        local tr = #scan.TrinketDebug > 0 and table.concat(scan.TrinketDebug, ", ") or "--"
                        Options.EH_LegacyScanTrinkets:SetText("Trinkets: " .. tr)
                    end

                    local info = H.PlayerTools.Info()
                    if Options.EH_LegacyVisualSelected then Options.EH_LegacyVisualSelected:SetText("Selected: " .. tostring(info.Name)) end
                    if Options.EH_LegacyVisualDistance then Options.EH_LegacyVisualDistance:SetText(info.Distance and info.Distance ~= math.huge and ("Distance: " .. math.floor(info.Distance) .. "m") or "Distance: --") end
                    if Options.EH_LegacyVisualHealth then Options.EH_LegacyVisualHealth:SetText(info.Health and ("HP: " .. math.floor(info.Health)) or "HP: --") end
                    if Options.EH_LegacyVisualRank then Options.EH_LegacyVisualRank:SetText("Rank: " .. tostring(info.Rank)) end
                    if Options.EH_LegacyMoveSelected then Options.EH_LegacyMoveSelected:SetText("Selected: " .. tostring(info.Name)) end
                end
            end)
            task.wait(0.25)
        end
    end)

    function L.Reset()
        for plr in pairs(equipped) do removeEquipped(plr) end
        restoreNoFogGlare()
    end

    print("[EndHub] legacy feature bridge loaded")
end

