return function(H)
    if not H.Visuals or not H.UI or not H.UI.Tabs or not H.UI.Tabs.Visuals then return end
    local C, F, cfg = H.Core, H.Farm, H.Config
    local rarityOf = H.TrinketRarity.Read
    cfg.TrinketESPRarities = cfg.TrinketESPRarities or {}
    cfg.TrinketESPDistance = tonumber(cfg.TrinketESPDistance) or 3000
    if cfg.TrinketESP == nil then cfg.TrinketESP = false end

    local group = H.UI.Tabs.Visuals:AddRightGroupbox("Trinket ESP")
    group:AddToggle("EH_TrinketESP", {
        Text = "Trinket ESP",
        Default = cfg.TrinketESP,
        Callback = function(v) cfg.TrinketESP = v end,
    })
    group:AddDropdown("EH_TrinketESPRarities", {
        Text = "Rarities",
        Values = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Exotic","Elite","Unknown"},
        Multi = true,
        Searchable = true,
        Callback = function(v)
            local out = {}
            for k, on in pairs(v or {}) do if on then out[k] = true end end
            cfg.TrinketESPRarities = out
        end,
    })
    if H.UI.Options.EH_TrinketESPRarities then H.UI.Options.EH_TrinketESPRarities:SetValue(cfg.TrinketESPRarities) end
    group:AddSlider("EH_TrinketESPDistance", {
        Text = "Max distance",
        Min = 100, Max = 10000, Default = cfg.TrinketESPDistance,
        Rounding = 0, Suffix = " studs",
        Callback = function(v) cfg.TrinketESPDistance = v end,
    })

    local colors = {
        Common = Color3.fromRGB(230,230,230), Uncommon = Color3.fromRGB(100,235,130),
        Rare = Color3.fromRGB(100,170,255), Epic = Color3.fromRGB(195,115,255),
        Legendary = Color3.fromRGB(255,195,65), Mythic = Color3.fromRGB(255,100,135),
    }
    local labels = {}
    local function remove(obj)
        local item = labels[obj]
        if item then pcall(function() item.Gui:Destroy() end) labels[obj] = nil end
    end
    local function clear()
        for obj in pairs(labels) do remove(obj) end
    end
    local function update()
        local pg = H.S.Player:FindFirstChild("PlayerGui")
        local root = C.Root()
        local folder = C.DropsFolder()
        if not cfg.TrinketESP or not pg or not root or not folder then clear() return end
        local seen = {}
        for _, obj in ipairs(folder:GetChildren()) do
            if C.IsTrinketDrop(obj) then
                local rarity = rarityOf(obj)
                local part = C.DropPart(obj)
                local d = part and (part.Position - root.Position).Magnitude
                if part and cfg.TrinketESPRarities[rarity] == true and d <= cfg.TrinketESPDistance then
                    seen[obj] = true
                    local item = labels[obj]
                    if not item then
                        local gui = Instance.new("BillboardGui")
                        gui.Name = "EndHub_TrinketESP"
                        gui.Size = UDim2.fromOffset(240, 48)
                        gui.StudsOffset = Vector3.new(0, 2.5, 0)
                        gui.AlwaysOnTop = true
                        gui.Parent = pg
                        local label = Instance.new("TextLabel")
                        label.Size = UDim2.fromScale(1, 1)
                        label.BackgroundTransparency = 1
                        label.TextSize = 14
                        label.Font = Enum.Font.SourceSansBold
                        label.TextStrokeTransparency = 0.25
                        label.Parent = gui
                        item = {Gui = gui, Label = label}
                        labels[obj] = item
                    end
                    item.Gui.Adornee = part
                    item.Gui.MaxDistance = cfg.TrinketESPDistance
                    item.Label.Text = F.LootName(obj) .. " [" .. rarity .. "]\n" .. math.floor(d) .. " studs"
                    item.Label.TextColor3 = colors[rarity] or Color3.fromRGB(220,220,220)
                end
            end
        end
        for obj in pairs(labels) do if not seen[obj] then remove(obj) end end
    end

    local previousReset = H.Visuals.Reset
    function H.Visuals.Reset()
        cfg.TrinketESP = false
        clear()
        return previousReset()
    end

    task.spawn(function()
        while not H.State.Unloaded do
            local ok = pcall(update)
            if not ok then clear() end
            task.wait(0.25)
        end
        clear()
    end)
end
