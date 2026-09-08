return function(H)
    local S = H.Sell
    local C = H.Core
    local Player = H.S.Player
    local RS = H.S.RS
    if not S or not C then return end

    local runtime = S.Runtime

    -- Match an exact inventory category + Tool name, never a partial name.
    -- These are the Common items identified in the user's inventory.
    H.Config.SellExactItems = H.Config.SellExactItems or {
        ["Trinket|Amulet"] = true, ["Trinket|Goblet"] = true,
        ["Trinket|Old Amulet"] = true, ["Trinket|Old Ring"] = true,
        ["Trinket|Ring"] = true,
        ["Tome|Enhancement Tome"] = true,
        ["Tome|Enhancement Tome (Sharpness I)"] = true,
    }
    H.Config.SellExactItems["Item|Bag"] = nil
    if H.Config.SellExactEnabled == nil then H.Config.SellExactEnabled = true end

    local function identity(entry)
        if entry.Category == "Tome" then
            local id = entry.Tool:FindFirstChild("EnhancementId")
            if id and id:IsA("StringValue") and id.Value ~= "" then
                -- Captured from the user's owned tome. Keep the existing
                -- selection key so saved choices continue to work.
                if id.Value == "Sharpness1" then
                    return "Tome|Enhancement Tome (Sharpness I)"
                end
                -- Different enhancements must not match the plain tome.
                return "Tome|EnhancementId=" .. id.Value
            end
        end
        return entry.Category .. "|" .. entry.Tool.Name
    end

    local function exactSelected(entry)
        return H.Config.SellExactEnabled and H.Config.SellExactItems[identity(entry)] == true
    end

    function S.ExportItemIdentities()
        local lines = {"[EndHub IDs] Exact category/name keys; metadata below is diagnostic, not an assumed stable ID."}
        for _, entry in ipairs(S.InventoryEntries()) do
            if C.NormalizeRarity(entry.Rarity) == "Common" or exactSelected(entry) then
                local fields = {}
                for key, value in pairs(entry.Tool:GetAttributes()) do
                    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                        fields[#fields + 1] = "attribute:" .. key .. "=" .. tostring(value)
                    end
                end
                for _, child in ipairs(entry.Tool:GetChildren()) do
                    if child:IsA("StringValue") or child:IsA("NumberValue") or child:IsA("IntValue") or child:IsA("BoolValue") then
                        fields[#fields + 1] = child.Name .. "=" .. tostring(child.Value)
                    end
                end
                table.sort(fields)
                lines[#lines + 1] = string.format("[EndHub ID] %s | x%d | %s", identity(entry), entry.Amount, table.concat(fields, "; "))
            end
        end
        local text = table.concat(lines, "\n")
        print(text)
        if setclipboard then pcall(setclipboard, text) end
        return text
    end

    local function isInside(ref, wanted)
        local node = ref and ref.Parent
        while node do
            if node.Name == wanted then return true end
            if node.Name == "InventoryGui" then break end
            node = node.Parent
        end
        return false
    end

    local frameMap = {
        WeaponFrame = "Weapon",
        ItemsFrame = "Item",
        TrinketsFrame = "Trinket",
        AccessoryFrame = "Accessory",
        PotionsFrame = "Potion",
        OutfitFrame = "Outfit",
        TomesFrame = "Tome",
        SummonFrame = "Summon",
        GemsFrame = "Gem",
    }

    local gemNames = {
        Sapphire = true, Topaz = true, Ruby = true,
        Emerald = true, Diamond = true, Amethyst = true,
    }

    local function categoryFromRef(ref)
        if not ref or not ref:IsA("ObjectValue") then return nil end
        local tool = ref.Value
        if not tool then return nil end

        -- IsTrinket is also true on weapons, outfits and potions.
        -- Only the inventory tab establishes the Trinket category.
        local node = ref.Parent
        while node do
            local mapped = frameMap[node.Name]
            if mapped then return mapped end
            if node.Name == "InventoryGui" then break end
            node = node.Parent
        end

        if tool:FindFirstChild("IsPotion") then return "Potion" end
        if tool:FindFirstChild("IsAccessory") then return "Accessory" end
        if tool:FindFirstChild("IsOutfit") then return "Outfit" end
        if tool:FindFirstChild("IsGem") then return "Gem" end
        if tool:FindFirstChild("IsSummon") then return "Summon" end
        if gemNames[tool.Name] and tool:FindFirstChild("IsEnchant") then return "Gem" end
        if tool:FindFirstChild("IsItem") then return "Item" end
        if tool:FindFirstChild("IsEnchant") then return "Tome" end

        local sword = tool:FindFirstChild("IsSword")
        if sword and sword:IsA("BoolValue") and sword.Value then return "Weapon" end
        return nil
    end

    local function stackCount(slot)
        if not slot then return 1 end
        local label = slot:FindFirstChild("ItemStack", true)
        if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
            local text = tostring(label.Text or "")
            local n = tonumber(string.match(text, "[xX]%s*(%d+)"))
                or tonumber(string.match(text, "(%d+)%s*[xX]"))
                or tonumber(string.match(text, "(%d+)"))
            if n and n > 0 then return math.floor(n) end
        end
        return 1
    end

    -- Classify inventory entries by their tab before using other metadata.
    function S.InventoryEntries()
        local pg = Player:FindFirstChild("PlayerGui")
        local inv = pg and pg:FindFirstChild("InventoryGui", true)
        if not inv then return {} end

        local out, seen = {}, {}
        for _, ref in ipairs(inv:GetDescendants()) do
            if ref:IsA("ObjectValue") and ref.Name == "ToolRef" then
                local tool = ref.Value
                if tool and tool.Parent and not seen[tool] then
                    local full = ref:GetFullName()
                    local bad = string.find(full, ".HotbarFrame.", 1, true)
                        or string.find(full, ".SellTrashFrame.", 1, true)
                    if not bad then
                        local category = categoryFromRef(ref)
                        if category then
                            seen[tool] = true
                            local slot = ref.Parent
                            out[#out + 1] = {
                                Tool = tool,
                                Ref = ref,
                                Slot = slot,
                                Category = category,
                                Rarity = C.ToolRarity(tool),
                                Amount = stackCount(slot),
                                IsTrinket = category == "Trinket",
                            }
                        end
                    end
                end
            end
        end
        return out
    end

    local function buildSplitPayloads()
        local normal, trinkets = {}, {}
        local normalStacks, trinketStacks = 0, 0
        runtime.CategoryMatches = {}
        runtime.RarityCounts = {}
        runtime.TrinketDebug = {}

        for _, category in ipairs(H.SellCategories or {}) do
            runtime.CategoryMatches[category] = 0
        end

        for _, entry in ipairs(S.InventoryEntries()) do
            local rarity = C.NormalizeRarity(entry.Rarity)
            local category = entry.Category
            runtime.RarityCounts[category] = runtime.RarityCounts[category] or {}
            runtime.RarityCounts[category][rarity] = (runtime.RarityCounts[category][rarity] or 0) + 1

            local filterOn = entry.Tool.Name ~= "Bag"
                and (exactSelected(entry) or S.GetFilter(rarity, category))
            if category == "Trinket" then
                local marker = entry.Tool:FindFirstChild("IsTrinket")
                local markerText = marker and marker:IsA("BoolValue") and tostring(marker.Value) or tostring(marker ~= nil)
                runtime.TrinketDebug[#runtime.TrinketDebug + 1] = string.format(
                    "%s | %s | x%d | filter=%s | IsTrinket=%s | BulkSell=%s | frame=%s",
                    tostring(entry.Tool.Name),
                    rarity,
                    tonumber(entry.Amount) or 1,
                    filterOn and "ON" or "OFF",
                    markerText,
                    entry.Tool:FindFirstChild("BulkSell") and "YES" or "NO",
                    isInside(entry.Ref, "TrinketsFrame") and "TrinketsFrame" or "other"
                )
            end

            if filterOn then
                runtime.CategoryMatches[category] = (runtime.CategoryMatches[category] or 0) + 1
                local amount = math.max(1, tonumber(entry.Amount) or 1)
                if category == "Trinket" then
                    trinketStacks = trinketStacks + 1
                    for _ = 1, amount do trinkets[#trinkets + 1] = entry.Tool end
                else
                    normalStacks = normalStacks + 1
                    for _ = 1, amount do normal[#normal + 1] = entry.Tool end
                end
            end
        end

        table.sort(runtime.TrinketDebug)
        runtime.SelectedTrinketItems = #trinkets
        runtime.SelectedTrinketStacks = trinketStacks
        runtime.SelectedNormalItems = #normal
        runtime.SelectedNormalStacks = normalStacks
        return normal, trinkets, normalStacks, trinketStacks
    end

    function S.BuildSplitPayloads()
        return buildSplitPayloads()
    end

    function S.BuildPayload()
        local normal, trinkets, normalStacks, trinketStacks = buildSplitPayloads()
        local payload = {}
        for _, tool in ipairs(normal) do payload[#payload + 1] = tool end
        for _, tool in ipairs(trinkets) do payload[#payload + 1] = tool end
        return payload, normalStacks + trinketStacks
    end

    function S.DebugTrinkets()
        buildSplitPayloads()
        return runtime.TrinketDebug
    end

    local function getSellRemote()
        local remotes = RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("SellItemsEvent")
        return remote and remote:IsA("RemoteEvent") and remote or nil
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
        task.delay(0.22, function()
            if not H.State.Unloaded then C.PressKey(0x31) end
        end)
    end

    local function fireSplit(trinketOnly)
        local remote = getSellRemote()
        if not remote then
            H.State.SellStatus = "SELL REMOTE MISSING"
            return false
        end

        local normal, trinkets, normalStacks, trinketStacks = buildSplitPayloads()
        if trinketOnly then normal, normalStacks = {}, 0 end

        runtime.LastSold = #normal + #trinkets
        runtime.LastStacks = normalStacks + trinketStacks

        if #normal == 0 and #trinkets == 0 then
            H.State.SellStatus = trinketOnly and "NO SELECTED TRINKETS" or "NO MATCHING ITEMS"
            return false
        end

        local ok, err = pcall(function()
            -- Keep trinkets in their own SellItemsEvent call. The captured
            -- normal game behavior sends the same owned Tool reference once
            -- per stack quantity; that exact shape is preserved here.
            if #normal > 0 then remote:FireServer(normal) end
            if #normal > 0 and #trinkets > 0 then task.wait(0.12) end
            if #trinkets > 0 then remote:FireServer(trinkets) end
        end)

        if not ok then
            H.State.SellStatus = "SELL ERROR: " .. tostring(err)
            warn("[EndHub Trinket Sell]", err)
            return false
        end

        H.State.SellStatus = string.format(
            "SENT %d NORMAL + %d TRINKETS",
            #normal, #trinkets
        )
        return true
    end


    -- A bounded diagnostic: use current owned references, one item per request.
    -- Inventory changes are observations, not server acknowledgements.
    local diagnosticGeneration = 0
    local previousStop = S.Stop
    function S.Stop()
        diagnosticGeneration = diagnosticGeneration + 1
        if previousStop then previousStop() end
    end

    function S.TestRemainingIndividually()
        if runtime.IndividualBusy then return end
        local seller = C.FindClement()
        local anchor = seller and C.NPCAnchor(seller)
        local root = C.Root()
        if not root or not anchor
            or (root.Position - anchor.Position).Magnitude > H.Config.SellerInteractDistance then
            H.State.SellStatus = "STAND BESIDE CLEMENT FOR TEST"
            return
        end
        -- Suspend automation so repeated NPC interaction cannot interrupt
        -- this isolated sale. The user can restart automation after the test.
        S.Stop()
        H.Config.AutoFarmSell = false
        if H.Farm and H.Farm.Stop then H.Farm.Stop() end
        local generation = diagnosticGeneration
        runtime.IndividualBusy = true
        task.spawn(function()
            local function cancelled()
                return H.State.Unloaded or generation ~= diagnosticGeneration
                    or H.Config.AutoSell or H.Config.AutoFarmSell
            end
            local function find(name)
                local pg = Player:FindFirstChild("PlayerGui")
                if not pg or not pg:FindFirstChild("InventoryGui", true) then return nil, nil end
                local total, first = 0, nil
                for _, entry in ipairs(S.InventoryEntries()) do
                    if entry.Category == "Trinket" and entry.Tool.Name == name then
                        total = total + entry.Amount
                        first = first or entry.Tool
                    end
                end
                return first, total
            end
            local ok, err = pcall(function()
                local remote = getSellRemote()
                if not remote then error("SELL REMOTE MISSING") end
                interactSeller(seller)
                task.wait(1)
                for _, name in ipairs({"Goblet", "Old Amulet"}) do
                    if cancelled() then return end
                    local tool, before = find(name)
                    if not tool then
                        print("[EndHub Individual] " .. name .. " | NOT FOUND / INVENTORY UNAVAILABLE")
                    else
                        H.State.SellStatus = "TESTING " .. name
                        print("[EndHub Individual] " .. name .. " | BEFORE=" .. tostring(before)
                            .. " | REF=" .. tool:GetFullName())
                        remote:FireServer({tool})
                        task.wait(1.5)
                        if cancelled() then return end
                        local _, after = find(name)
                        print("[EndHub Individual] " .. name .. " | AFTER=" .. tostring(after)
                            .. " | " .. (after and after < before and "COUNT DECREASED"
                                or after and "NO DECREASE" or "CANNOT VERIFY"))
                    end
                end
                H.State.SellStatus = "INDIVIDUAL TEST COMPLETE - SEE CONSOLE"
            end)
            runtime.IndividualBusy = false
            if not ok then
                warn("[EndHub Individual] " .. tostring(err))
                H.State.SellStatus = "INDIVIDUAL TEST ERROR"
            end
        end)
    end

    function S.TestSellTrinketsOnly()
        runtime.TrinketOnlyOnce = true
        runtime.OneShot = true
        runtime.InteractOnly = false
        runtime.SellerReady = false
        runtime.ReadyAt = 0
        H.State.SellStatus = "QUEUED TRINKET-ONLY TEST"
    end

    -- Replace only the seller step. Farm logic, saved Clement position,
    -- filters and all other features remain untouched.
    function S.Step()
        if H.State.Unloaded or runtime.IndividualBusy then return end
        local active = H.Config.AutoSell or runtime.OneShot or runtime.InteractOnly
        if not active then return end

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
            if d > H.Config.SellerInteractDistance then
                H.State.SellStatus = "TP SAVED SELLER AREA"
                C.Teleport(saved + Vector3.new(0, 4, 0))
            else
                H.State.SellStatus = "WAIT CLEMENT STREAM"
            end
            return
        end

        local part = C.NPCAnchor(seller)
        if not part then
            H.State.SellStatus = "SELLER INVALID"
            return
        end
        C.SaveSellerPosition(part.Position)

        local destination = part.Position + Vector3.new(0, 2.5, 0)
        if (root.Position - destination).Magnitude > H.Config.SellerInteractDistance then
            H.State.SellStatus = "TP TO CLEMENT"
            C.Teleport(destination, part.Position)
            runtime.SellerReady = false
            runtime.ReadyAt = 0
            return
        end

        C.Noclip(true)

        if tick() - runtime.LastInteract >= H.Config.SellerInteractInterval then
            runtime.LastInteract = tick()
            H.State.SellStatus = "INTERACTING"
            interactSeller(seller)
            runtime.SellerReady = true
            runtime.ReadyAt = tick()

            if runtime.InteractOnly then
                task.delay(0.45, function()
                    if H.State.Unloaded then return end
                    runtime.InteractOnly = false
                    runtime.SellerReady = false
                    H.State.SellStatus = "INTERACTED"
                end)
                return
            end
        end

        if runtime.SellerReady
        and tick() - runtime.ReadyAt >= 0.35
        and tick() - runtime.LastSell >= H.Config.SellInterval then
            runtime.LastSell = tick()
            local trinketOnly = runtime.TrinketOnlyOnce == true
            local sold = fireSplit(trinketOnly)

            if runtime.OneShot then
                runtime.OneShot = false
                runtime.TrinketOnlyOnce = false
                runtime.SellerReady = false
                if sold then
                    H.State.SellStatus = trinketOnly and "TRINKET TEST SENT" or "ONE-SHOT SENT"
                end
            end
        end
    end

    -- UI diagnostics/test controls.
    local tabs = H.UI and H.UI.Tabs
    local options = H.UI and H.UI.Options
    -- Apply the requested Common/Trinket selection once. Persist the marker
    -- with the regular config so later user filter changes survive reloads.
    if not H.Config.TrinketCategoryFilterMigrated then
        S.SetFilter("Common", "Trinket", true)
        if options and options.EH_Sell_Common then
            local selected = {}
            for _, category in ipairs(H.SellCategories or {}) do
                if S.GetFilter("Common", category) then selected[category] = true end
            end
            options.EH_Sell_Common:SetValue(selected)
        end
        H.Config.TrinketCategoryFilterMigrated = true
    end

    if tabs and tabs.Sell then
        local exact = tabs.Sell:AddLeftGroupbox("Sell by Exact Item")
        exact:AddToggle("EH_SellExactEnabled", {
            Text = "Include exact items regardless of rarity",
            Default = H.Config.SellExactEnabled,
            Callback = function(value) H.Config.SellExactEnabled = value end,
        })
        local function choices()
            local values, seen = {}, {}
            for key in pairs(H.Config.SellExactItems) do seen[key] = true end
            for _, entry in ipairs(S.InventoryEntries()) do seen[identity(entry)] = true end
            for key in pairs(seen) do values[#values + 1] = key end
            table.sort(values)
            return values
        end
        local initialSelection = {}
        for key, value in pairs(H.Config.SellExactItems) do initialSelection[key] = value end
        exact:AddDropdown("EH_SellExactItems", {
            Text = "Exact items to sell", Values = choices(), Multi = true,
            Searchable = true,
            Callback = function(value)
                H.Config.SellExactItems = type(value) == "table" and value or {}
            end,
        })
        if options and options.EH_SellExactItems then
            options.EH_SellExactItems:SetValue(initialSelection)
        end
        exact:AddButton({Text = "REFRESH INVENTORY ITEM LIST", Func = function()
            if options and options.EH_SellExactItems then
                local selected = {}
                for key, value in pairs(H.Config.SellExactItems) do selected[key] = value end
                options.EH_SellExactItems:SetValues(choices())
                options.EH_SellExactItems:SetValue(selected)
            end
        end})
        exact:AddButton({Text = "COPY COMMON ITEM IDENTITIES", Func = function()
            S.ExportItemIdentities()
        end})
        local g = tabs.Sell:AddRightGroupbox("Trinket Sell Fix")
        g:AddButton({Text = "TEST GOBLET + OLD AMULET INDIVIDUALLY", Func = function()
            S.TestRemainingIndividually()
        end})
        g:AddButton({Text = "TEST SELL SELECTED TRINKETS ONLY", Func = function()
            S.TestSellTrinketsOnly()
        end})
        g:AddButton({Text = "REFRESH TRINKET DIAGNOSTIC", Func = function()
            local lines = S.DebugTrinkets()
            H.State.SellStatus = "TRINKET DEBUG: " .. tostring(#lines) .. " STACKS"
            for _, line in ipairs(lines) do print("[EndHub Trinket] " .. line) end
        end})
        g:AddLabel("EH_TrinketFixCount", {Text = "Selected trinkets: --", DoesWrap = true})
        g:AddLabel("EH_TrinketFixDetail", {Text = "Detected: --", DoesWrap = true})

        task.spawn(function()
            while not H.State.Unloaded do
                pcall(function()
                    buildSplitPayloads()
                    if options and options.EH_TrinketFixCount then
                        options.EH_TrinketFixCount:SetText(
                            "Selected trinkets: " .. tostring(runtime.SelectedTrinketItems or 0)
                            .. " items / " .. tostring(runtime.SelectedTrinketStacks or 0) .. " stacks"
                        )
                    end
                    if options and options.EH_TrinketFixDetail then
                        local first = runtime.TrinketDebug and runtime.TrinketDebug[1]
                        options.EH_TrinketFixDetail:SetText(
                            "Detected: " .. tostring(runtime.TrinketDebug and #runtime.TrinketDebug or 0)
                            .. (first and (" | " .. first) or "")
                        )
                    end
                end)
                task.wait(0.75)
            end
        end)
    end

    print("[EndHub] trinket sell: tab classification fix loaded")
end
