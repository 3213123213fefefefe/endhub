return function(H)
    H.Sell = {}
    local S = H.Sell
    local C = H.Core
    local Player = H.S.Player
    local RS = H.S.RS

    local runtime = {
        LastInteract = 0,
        LastSell = 0,
        LastSold = 0,
        LastStacks = 0,
        SellerReady = false,
        CategoryMatches = {},
    }
    S.Runtime = runtime

    local defaults = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Exotic","Unknown"}
    local categories = {"Weapon","Item","Trinket","Accessory","Potion","Outfit","Tome","Summon","Gem"}
    H.SellRarities = defaults
    H.SellCategories = categories

    local function ensureBucket(rarity)
        rarity = C.NormalizeRarity(rarity)
        H.Config.SellByRarity[rarity] = H.Config.SellByRarity[rarity] or {}
        local b = H.Config.SellByRarity[rarity]
        for _, cat in ipairs(categories) do
            if b[cat] == nil then b[cat] = false end
        end
        return b
    end

    for _, rarity in ipairs(defaults) do ensureBucket(rarity) end

    function S.SetFilter(rarity, category, value)
        local b = ensureBucket(rarity)
        if b[category] ~= nil then
            b[category] = value and true or false
        end
    end

    local function categoryFromRef(ref)
        local node = ref and ref.Parent
        while node do
            local mapped = H.SellCategoryFrames[node.Name]
            if mapped then return mapped end
            if node.Name == "InventoryGui" then break end
            node = node.Parent
        end

        local tool = ref and ref.Value
        if not tool then return nil end

        local tr = tool:FindFirstChild("IsTrinket")
        if tr and tr:IsA("BoolValue") and tr.Value then return "Trinket" end
        if tool:FindFirstChild("IsPotion") then return "Potion" end
        if tool:FindFirstChild("IsAccessory") then return "Accessory" end
        if tool:FindFirstChild("IsOutfit") then return "Outfit" end
        if tool:FindFirstChild("IsItem") then return "Item" end
        if tool:FindFirstChild("IsEnchant") then return "Tome" end
        if tool:FindFirstChild("IsSummon") then return "Summon" end
        local sword = tool:FindFirstChild("IsSword")
        if sword and sword:IsA("BoolValue") and sword.Value then return "Weapon" end
        return nil
    end

    local function stackCount(slot)
        if not slot then return 1 end
        local label = slot:FindFirstChild("ItemStack", true)
        if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
            local n = tonumber(string.match(tostring(label.Text or ""), "[xX](%d+)"))
            if n and n > 0 then return math.floor(n) end
        end
        return 1
    end

    function S.InventoryEntries()
        local pg = Player:FindFirstChild("PlayerGui")
        local inv = pg and pg:FindFirstChild("InventoryGui")
        if not inv then return {} end

        local out, seen = {}, {}
        for _, obj in ipairs(inv:GetDescendants()) do
            if obj:IsA("ObjectValue") and obj.Name == "ToolRef" then
                local tool = obj.Value
                if tool and tool.Parent and not seen[tool] then
                    local full = obj:GetFullName()
                    if not string.find(full, ".HotbarFrame.", 1, true)
                    and not string.find(full, ".SellTrashFrame.", 1, true) then
                        local cat = categoryFromRef(obj)
                        if cat then
                            seen[tool] = true
                            out[#out + 1] = {
                                Tool = tool,
                                Category = cat,
                                Rarity = C.ToolRarity(tool),
                                Amount = stackCount(obj.Parent),
                            }
                        end
                    end
                end
            end
        end
        return out
    end

    function S.BuildPayload()
        local payload, stacks = {}, 0
        runtime.CategoryMatches = {}

        for _, entry in ipairs(S.InventoryEntries()) do
            local bucket = H.Config.SellByRarity[C.NormalizeRarity(entry.Rarity)]
            if bucket and bucket[entry.Category] then
                stacks = stacks + 1
                runtime.CategoryMatches[entry.Category] = (runtime.CategoryMatches[entry.Category] or 0) + 1
                for i = 1, math.max(1, entry.Amount) do
                    payload[#payload + 1] = entry.Tool
                end
            end
        end
        return payload, stacks
    end

    function S.SellMatching()
        local remotes = RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("SellItemsEvent")
        if not remote or not remote:IsA("RemoteEvent") then
            H.State.SellStatus = "SELL REMOTE MISSING"
            return false
        end

        local payload, stacks = S.BuildPayload()
        runtime.LastSold = #payload
        runtime.LastStacks = stacks

        if #payload == 0 then
            H.State.SellStatus = "NO MATCHING ITEMS"
            return false
        end

        remote:FireServer(payload)
        H.State.SellStatus = "SOLD " .. tostring(#payload) .. " / " .. tostring(stacks) .. " STACKS"
        return true
    end

    local function interactSeller(seller)
        local remotes = RS:FindFirstChild("Remotes")
        if remotes then
            local register = remotes:FindFirstChild("RegisterNPCInteraction")
            local dialog = remotes:FindFirstChild("DialogEvent")
            if register and register:IsA("RemoteEvent") then
                pcall(function() register:FireServer("Clement, Merchant") end)
            end
            if dialog and dialog:IsA("RemoteEvent") then
                pcall(function() dialog:FireServer("start", seller, 1) end)
            end
        end

        C.PressKey(0x45)
        task.delay(0.18, function()
            if not H.State.Unloaded then C.PressKey(0x31) end
        end)
    end

    function S.Start()
        H.Config.AutoSell = true
        runtime.SellerReady = false
        runtime.LastInteract = 0
        runtime.LastSell = 0
        H.State.SellStatus = "STARTING"
    end

    function S.Stop()
        H.Config.AutoSell = false
        runtime.SellerReady = false
        H.State.SellStatus = "IDLE"
    end

    function S.Step()
        if H.State.Unloaded or not H.Config.AutoSell then return end
        H.State.Running = false

        local root = C.Root()
        if not root then
            H.State.SellStatus = "WAIT CHARACTER"
            return
        end

        local seller = C.FindClement()
        if not seller then
            local saved = C.GetSavedSeller()
            if not saved then
                H.State.SellStatus = "VISIT CLEMENT ONCE"
                return
            end

            local d = (root.Position - saved).Magnitude
            if d > 25 then
                H.State.SellStatus = "TP SAVED SELLER AREA"
                C.Teleport(saved + Vector3.new(0, 4, 0))
            else
                H.State.SellStatus = "WAIT SELLER STREAM"
            end
            return
        end

        local part = C.NPCAnchor(seller)
        if not part then return end
        local destination = part.Position + Vector3.new(0, 2.5, 0)
        if (root.Position - destination).Magnitude > H.Config.SellerInteractDistance then
            H.State.SellStatus = "TP TO CLEMENT"
            C.Teleport(destination, part.Position)
            runtime.SellerReady = false
            return
        end

        C.Noclip(true)

        if tick() - runtime.LastInteract >= H.Config.SellerInteractInterval then
            runtime.LastInteract = tick()
            H.State.SellStatus = "INTERACTING"
            interactSeller(seller)
            runtime.SellerReady = true
        end

        if runtime.SellerReady and tick() - runtime.LastSell >= H.Config.SellInterval then
            runtime.LastSell = tick()
            S.SellMatching()
        end
    end

    function S.AutoFarmStep()
        if H.State.Unloaded or not H.Config.AutoFarmSell then return end
        local cur, max = C.ReadCapacity()
        if not cur or not max then return end

        if H.State.FarmSellPhase == "FARM" then
            if H.State.InventoryPercent >= H.Config.SellAtPercent then
                H.State.FarmSellPhase = "SELL"
                if H.Farm then H.Farm.Stop() end
                S.Start()
            else
                H.Config.AutoSell = false
                if H.Farm and not H.State.Running then H.Farm.Start() end
            end
        else
            H.Config.AutoSell = true
            if H.State.InventoryPercent <= H.Config.ResumeAtPercent then
                S.Stop()
                H.State.FarmSellPhase = "FARM"
                if H.Farm then H.Farm.Start() end
            end
        end
    end

    C.Connect(H.S.RunService.Heartbeat, function()
        if H.State.Unloaded then return end
        S.AutoFarmStep()
        S.Step()
    end)
end
