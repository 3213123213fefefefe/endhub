return function(H)
    local S = H.Sell
    local C = H.Core
    local Player = H.S.Player
    local RS = H.S.RS
    if not S or not C then return end

    local runtime = S.Runtime
    -- Prefer coordinates actually observed in this map over embedded defaults.
    local mapKey = tostring(game.PlaceId)
    H.Config.ObservedSellerByPlace = H.Config.ObservedSellerByPlace or {}
    local oldSaveSeller, oldGetSeller = C.SaveSellerPosition, C.GetSavedSeller
    function C.SaveSellerPosition(pos)
        if typeof(pos) == "Vector3" then
            H.Config.ObservedSellerByPlace[mapKey] = {pos.X, pos.Y, pos.Z}
        end
        return oldSaveSeller(pos)
    end
    function C.GetSavedSeller()
        -- Previously captured merchant coordinates for this map.
        if mapKey == "125503525638054" then
            return Vector3.new(242.51593, 188.5, 1.00323868)
        end
        local pos = H.Config.ObservedSellerByPlace[mapKey]
        if type(pos) == "table" and tonumber(pos[1]) and tonumber(pos[2]) and tonumber(pos[3]) then
            return Vector3.new(tonumber(pos[1]), tonumber(pos[2]), tonumber(pos[3]))
        end
        return oldGetSeller()
    end
    local function sellerDestination(pos)
        local distance = math.max(0.2, tonumber(H.Config.SellerInteractDistance) or 1.65)
        return pos + Vector3.new(0, 0, math.min(1, distance * 0.5))
    end
    local function approachSeller(pos, missing)
        local root = C.Root()
        if not root then return end
        if missing and tick() - (runtime.LastStreamRequest or 0) >= 3 and not runtime.StreamPending then
            runtime.LastStreamRequest = tick()
            runtime.StreamPending = true
            task.spawn(function()
                local ok, err = pcall(function() Player:RequestStreamAroundAsync(pos, 2) end)
                runtime.StreamPending = false
                if not ok then print("[EndHub Seller] streaming request failed: " .. tostring(err)) end
            end)
        end
        local destination = sellerDestination(pos)
        if (root.Position - destination).Magnitude > 0.5 and tick() - (runtime.LastSellerTP or 0) >= 0.5 then
            runtime.LastSellerTP = tick()
            C.Noclip(true)
            C.Teleport(destination, pos)
            runtime.SellerReady = false
            runtime.ReadyAt = 0
            if tick() - (runtime.LastSellerLog or 0) >= 2 then
                runtime.LastSellerLog = tick()
                print("[EndHub Seller] approach | npcLoaded=" .. tostring(not missing) .. " | destination=" .. tostring(destination))
            end
        end
    end

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

    -- Always included in an active sale, independent of saved UI filters.
    local alwaysSellTrinkets = {
        ["Amulet"] = true,
        ["Goblet"] = true,
        ["Old Amulet"] = true,
        ["Old Ring"] = true,
        ["Ring"] = true,
    }
    local function exactSelected(entry)
        if entry.Category == "Trinket" and alwaysSellTrinkets[entry.Tool.Name] then
            return true
        end
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

    -- UI tabs establish categories; live owned instances establish quantities.
    -- Keep category knowledge while the UI retains references to sold instances.
    local categoryByName = {}
    local categoryByTool = setmetatable({}, {__mode = "k"})
    function S.InventoryEntries()
        local pg = Player:FindFirstChild("PlayerGui")
        local inv = pg and pg:FindFirstChild("InventoryGui", true)
        if inv then
            for _, ref in ipairs(inv:GetDescendants()) do
                if ref:IsA("ObjectValue") and ref.Name == "ToolRef" and ref.Value then
                    local full = ref:GetFullName()
                    if not string.find(full, ".HotbarFrame.", 1, true)
                        and not string.find(full, ".SellTrashFrame.", 1, true) then
                        local tool = ref.Value
                        local category = categoryFromRef(ref)
                        if category then
                            categoryByTool[tool] = category
                            local prior = categoryByName[tool.Name]
                            if prior == nil then categoryByName[tool.Name] = category
                            elseif prior ~= category then categoryByName[tool.Name] = false end
                        end
                    end
                end
            end
        end
        local out, seen = {}, {}
        local function collect(container)
            if not container then return end
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and not seen[tool] then
                    local category = categoryByTool[tool] or categoryByName[tool.Name]
                    local marker = tool:FindFirstChild("IsTrinket")
                    if alwaysSellTrinkets[tool.Name] and marker and marker:IsA("BoolValue") and marker.Value then
                        category = "Trinket"
                    end
                    if category then
                        seen[tool] = true
                        out[#out + 1] = {
                            Tool = tool,
                            Category = category,
                            Rarity = C.ToolRarity(tool),
                            Amount = 1,
                            IsTrinket = category == "Trinket",
                        }
                    end
                end
            end
        end
        collect(Player:FindFirstChild("Backpack"))
        collect(Player.Character)
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
        local direct = false
        if remotes then
            local register = remotes:FindFirstChild("RegisterNPCInteraction")
            local dialog = remotes:FindFirstChild("DialogEvent")
            if register and register:IsA("RemoteEvent") then
                pcall(function() register:FireServer("Clement, Merchant") end)
            end
            if dialog and dialog:IsA("RemoteEvent") then
                direct = pcall(function() dialog:FireServer("start", seller, 1) end)
            end
        end
        if direct then return end
        C.PressKey(0x45)
        task.delay(0.22, function()
            if not H.State.Unloaded then C.PressKey(0x31) end
        end)
    end

    local function remainingSelected()
        local pg = Player:FindFirstChild("PlayerGui")
        if not Player:FindFirstChild("Backpack") or not Player.Character
            or not pg or not pg:FindFirstChild("InventoryGui", true) then return nil end
        local count = 0
        for _, entry in ipairs(S.InventoryEntries()) do
            if entry.Tool.Name ~= "Bag"
                and (exactSelected(entry) or S.GetFilter(C.NormalizeRarity(entry.Rarity), entry.Category)) then
                count = count + entry.Amount
            end
        end
        return count
    end

    local previousStart = S.Start
    function S.Start()
        runtime.SaleVerifiedEmpty = false
        if previousStart then previousStart() end
    end

    local previousAutoFarmStep = S.AutoFarmStep
    function S.AutoFarmStep()
        if H.State.Unloaded or not H.Config.AutoFarmSell then return end
        if H.State.FarmSellPhase ~= "SELL" then
            return previousAutoFarmStep()
        end
        -- Capacity alone cannot authorize collecting again.
        if H.State.Running and H.Farm then H.Farm.Stop() end
        local remaining = remainingSelected()
        if runtime.SaleBusy or not runtime.SaleVerifiedEmpty or remaining ~= 0 then
            if remaining ~= 0 then runtime.SaleVerifiedEmpty = false end
            H.Config.AutoSell = true
            return
        end
        local trip = runtime.SellerTrip
        if trip then
            local root = C.Root()
            if not root then H.State.SellStatus = "WAIT CHARACTER BEFORE RETURN" return end
            if Player.Character ~= trip.Character then
                H.Config.AutoFarmSell = false
                H.Config.AutoSell = false
                H.State.SellStatus = "CHARACTER CHANGED - RETURN PAUSED"
                return
            end
            H.Config.AutoSell = false
            H.State.SellStatus = "RETURN TO COLLECTION POSITION"
            if not trip.ReturnStarted or (root.Position - trip.Origin.Position).Magnitude > 3 then
                if not trip.LastReturn or tick() - trip.LastReturn >= 0.5 then
                    trip.LastReturn = tick()
                    trip.ReturnStarted = tick()
                    C.Noclip(true)
                    root.CFrame = trip.Origin
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    print("[EndHub Seller] returning to collection origin=" .. tostring(trip.Origin.Position))
                end
                return
            end
            if tick() - trip.ReturnStarted < 0.3 then return end
        end
        S.Stop()
        runtime.SellerTrip = nil
        H.State.FarmSellPhase = "FARM"
        print("[EndHub AutoSell] inventory verified: 0 selected items; returned to origin; resuming collection")
        if H.Farm then H.Farm.Start() end
    end

    local saleGeneration = 0

    local function fireSplit(trinketOnly)
        if runtime.SaleBusy then return end
        runtime.SaleBusy = true
        runtime.LastSold = 0
        runtime.LastStacks = 0
        local generation = saleGeneration
        task.spawn(function()
            local decreased, sent, failures = 0, 0, {}
            local deadline = tick() + 120
            local function cancelled()
                return H.State.Unloaded or generation ~= saleGeneration
                    or not (H.Config.AutoSell or runtime.OneShot)
            end
            local function snapshot()
                local pg = Player:FindFirstChild("PlayerGui")
                if not pg or not pg:FindFirstChild("InventoryGui", true) then return nil end
                local entries, counts = S.InventoryEntries(), {}
                for _, entry in ipairs(entries) do
                    local key = identity(entry)
                    counts[key] = (counts[key] or 0) + entry.Amount
                end
                return entries, counts
            end
            local function finish(message)
                if cancelled() then return end
                runtime.SaleVerifiedEmpty = false
                -- Confirm completion repeatedly while SaleBusy blocks the farm transition.
                local confirmed = string.sub(message, 1, 5) == "DONE:"
                if confirmed then
                    for _ = 1, 4 do
                        if cancelled() then return end
                        if remainingSelected() ~= 0 then confirmed = false break end
                        task.wait(0.25)
                    end
                    if cancelled() then return end
                    if remainingSelected() ~= 0 then confirmed = false end
                end
                runtime.SaleVerifiedEmpty = confirmed
                runtime.OneShot = false
                runtime.TrinketOnlyOnce = false
                runtime.SellerReady = false
                H.Config.AutoSell = false
                if H.Config.AutoFarmSell and not confirmed then
                    H.Config.AutoFarmSell = false
                    if H.Farm then H.Farm.Stop() end
                    message = message .. " | FARM PAUSED: SALE NOT CONFIRMED COMPLETE"
                end
                print("[EndHub AutoSell] finish | remaining=" .. tostring(remainingSelected())
                    .. " | confirmedEmpty=" .. tostring(confirmed) .. " | " .. message)
                H.State.SellStatus = message
            end
            local ok, err = pcall(function()
                local remote = getSellRemote()
                if not remote then finish("SELL REMOTE MISSING") return end
                while not cancelled() and tick() < deadline do
                    local entries, counts = snapshot()
                    if not entries then finish("INVENTORY UNAVAILABLE - SELL PAUSED") return end
                    local chosen
                    for _, entry in ipairs(entries) do
                        local key = identity(entry)
                        local selected = entry.Tool.Name ~= "Bag"
                            and (exactSelected(entry) or S.GetFilter(C.NormalizeRarity(entry.Rarity), entry.Category))
                        if selected and (not trinketOnly or entry.Category == "Trinket")
                            and (failures[key] or 0) < 2 then
                            chosen = entry
                            break
                        end
                    end
                    if not chosen then
                        -- Rebuilds can briefly remove every ToolRef from the UI.
                        local refreshUntil = tick() + 3
                        repeat
                            if cancelled() then return end
                            task.wait(0.25)
                            local refreshed = snapshot()
                            if refreshed then
                                for _, candidate in ipairs(refreshed) do
                                    local candidateKey = identity(candidate)
                                    local selected = candidate.Tool.Name ~= "Bag"
                                        and (exactSelected(candidate) or S.GetFilter(C.NormalizeRarity(candidate.Rarity), candidate.Category))
                                    if selected and (not trinketOnly or candidate.Category == "Trinket")
                                        and (failures[candidateKey] or 0) < 2 then
                                        chosen = candidate
                                        break
                                    end
                                end
                            end
                        until chosen or tick() >= refreshUntil
                        if chosen then
                            print("[EndHub AutoSell] inventory refreshed; rebuilding sale selection")
                            entries, counts = snapshot()
                            if not entries then finish("INVENTORY UNAVAILABLE - SELL PAUSED") return end
                        else
                        print("[EndHub AutoSell] no eligible items after 3s recheck")
                        local blocked = 0
                        for _, attempts in pairs(failures) do if attempts >= 2 then blocked = blocked + 1 end end
                        finish(string.format("DONE: COUNT DECREASED %d | UNCHANGED %d", decreased, blocked))
                        return
                        end
                    end
                    local key, tool = identity(chosen), chosen.Tool
                    local before = counts[key] or 0
                    local seller = C.FindClement()
                    local part = seller and C.NPCAnchor(seller)
                    local root = C.Root()
                    if not part or not root or (root.Position - part.Position).Magnitude > H.Config.SellerInteractDistance then
                        finish("SELLER OUT OF RANGE - SELL PAUSED") return
                    end
                    -- Batch distinct owned instances of the same standard trinket.
                    local payload, included = {}, {}
                    local batchTrinket = chosen.Category == "Trinket" and alwaysSellTrinkets[tool.Name] == true
                    if batchTrinket then
                        local backpack = Player:FindFirstChild("Backpack")
                        local character = Player.Character
                        for _, entry in ipairs(entries) do
                            local candidate = entry.Tool
                            local owned = (backpack and candidate:IsDescendantOf(backpack))
                                or (character and candidate:IsDescendantOf(character))
                            if identity(entry) == key and owned and not included[candidate] then
                                included[candidate] = true
                                payload[#payload + 1] = candidate
                                if #payload >= 50 then break end
                            end
                        end
                    else
                        payload[1] = tool
                    end
                    if #payload == 0 then
                        finish("OWNED REFERENCES CHANGED - RETRY SALE")
                        return
                    end
                    H.State.SellStatus = "SELLING " .. chosen.Tool.Name .. " x" .. #payload
                    print("[EndHub AutoSell] " .. key .. " | BEFORE=" .. before .. " | REQUESTED=" .. #payload)
                    remote:FireServer(payload)
                    sent = sent + 1
                    runtime.LastSell = tick()
                    runtime.LastStacks = sent
                    -- Missing UI references are not proof that the stack was sold.
                    local verificationStarted = tick()
                    local verifyUntil = verificationStarted + 5
                    local ownedBackpack = Player:FindFirstChild("Backpack")
                    local ownedCharacter = Player.Character
                    local singleOwned = chosen.Amount == 1 and (
                        (ownedBackpack and tool:IsDescendantOf(ownedBackpack))
                        or (ownedCharacter and tool:IsDescendantOf(ownedCharacter)))
                    local liveTrinket = batchTrinket or singleOwned == true
                    local minimumWait = liveTrinket and 0.25
                        or math.max(1.5, tonumber(H.Config.SellInterval) or 0.8)
                    local afterEntries, afterCounts
                    local previousAfter, stableSince
                    repeat
                        if cancelled() then return end
                        task.wait(liveTrinket and 0.05 or 0.20)
                        afterEntries, afterCounts = snapshot()
                        local observed = afterEntries and (afterCounts[key] or 0) or nil
                        if observed ~= previousAfter then
                            previousAfter = observed
                            stableSince = tick()
                        end
                        local stableFor = stableSince and tick() - stableSince or 0
                        local elapsed = tick() - verificationStarted
                        if liveTrinket then
                            local backpack = Player:FindFirstChild("Backpack")
                            local character = Player.Character
                            local stillOwned = false
                            for _, submitted in ipairs(payload) do
                                if (backpack and submitted:IsDescendantOf(backpack))
                                    or (character and submitted:IsDescendantOf(character)) then
                                    stillOwned = true
                                    break
                                end
                            end
                            if backpack and character and not stillOwned
                                and observed and observed < before
                                and elapsed >= minimumWait and stableFor >= 0.10 then break end
                        else
                            if observed and observed > 0 and observed < before
                                and elapsed >= minimumWait and stableFor >= 0.5 then break end
                            -- Other items still depend on UI stack references.
                            if observed == 0 and elapsed >= math.max(3, minimumWait)
                                and stableFor >= 2.5 then break end
                        end
                    until tick() >= verifyUntil
                    if not afterEntries then finish("CANNOT VERIFY - SELL PAUSED") return end
                    local after = afterCounts[key] or 0
                    print("[EndHub AutoSell] verified " .. key .. " | visible=" .. after
                        .. " | waited=" .. string.format("%.2f", tick() - verificationStarted))
                    if after < before then
                        decreased = decreased + before - after
                        runtime.LastSold = decreased
                        failures[key] = 0
                        print("[EndHub AutoSell] " .. key .. " | AFTER=" .. after .. " | COUNT DECREASED")
                    else
                        failures[key] = (failures[key] or 0) + 1
                        print("[EndHub AutoSell] " .. key .. " | AFTER=" .. after .. " | NO DECREASE")
                        if failures[key] < 2 then
                            local seller = C.FindClement()
                            local part = seller and C.NPCAnchor(seller)
                            local root = C.Root()
                            if not part or not root or (root.Position - part.Position).Magnitude > H.Config.SellerInteractDistance then
                                finish("SELLER OUT OF RANGE - SELL PAUSED") return
                            end
                            interactSeller(seller)
                            task.wait(1)
                        end
                    end
                end
                if not cancelled() then finish("SELL TIME LIMIT - CHECK REMAINING ITEMS") end
            end)
            if not ok and not cancelled() then
                warn("[EndHub AutoSell] " .. tostring(err))
                finish("SELL ERROR: " .. tostring(err))
            end
            runtime.SaleBusy = false
        end)
    end

    -- A bounded diagnostic: use current owned references, one item per request.
    -- Inventory changes are observations, not server acknowledgements.
    local diagnosticGeneration = 0
    local previousStop = S.Stop
    function S.Stop()
        runtime.SellerTrip = nil
        diagnosticGeneration = diagnosticGeneration + 1
        saleGeneration = saleGeneration + 1
        runtime.TrinketOnlyOnce = false
        if previousStop then previousStop() end
    end

    function S.TestRemainingIndividually()
        if runtime.IndividualBusy or runtime.SaleBusy then return end
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

    local previousStart, previousMatching = S.Start, S.SellMatching
    function S.Start()
        saleGeneration = saleGeneration + 1
        runtime.TrinketOnlyOnce = false
        if previousStart then previousStart() end
    end
    function S.SellMatching()
        saleGeneration = saleGeneration + 1
        runtime.TrinketOnlyOnce = false
        if previousMatching then previousMatching() end
    end

    function S.TestSellTrinketsOnly()
        saleGeneration = saleGeneration + 1
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
        if H.State.Unloaded or H.State.Ready == false or runtime.IndividualBusy or runtime.SaleBusy then return end
        local active = H.Config.AutoSell or runtime.OneShot or runtime.InteractOnly
        if not active then return end

        H.State.Running = false
        local root = C.Root()
        if not root then
            H.State.SellStatus = "WAIT CHARACTER"
            return
        end

        if not runtime.SellerTrip then
            local saved = C.GetSavedSeller()
            if not saved then
                H.State.SellStatus = "SELLER COORDINATES MISSING"
                return
            end
            runtime.SellerTrip = {
                Origin = root.CFrame,
                Character = Player.Character,
                Destination = saved,
            }
            H.State.SellStatus = "TP FIXED SELLER COORDINATES"
            C.Noclip(true)
            C.Teleport(saved)
            runtime.SellerReady = false
            runtime.ReadyAt = 0
            print("[EndHub Seller] trip started | origin=" .. tostring(runtime.SellerTrip.Origin.Position)
                .. " | fixedDestination=" .. tostring(saved))
            return
        end

        local seller = C.FindClement()
        if not seller then
            local saved = C.GetSavedSeller()
            if not saved then
                H.State.SellStatus = "VISIT CLEMENT ONCE"
                return
            end

            H.State.SellStatus = "APPROACH SAVED CLEMENT / WAIT STREAM"
            approachSeller(saved, true)
            return
        end

        local part = C.NPCAnchor(seller)
        if not part then
            H.State.SellStatus = "SELLER INVALID"
            return
        end
        C.SaveSellerPosition(part.Position)

        if (root.Position - part.Position).Magnitude > H.Config.SellerInteractDistance then
            H.State.SellStatus = "TP TO CLEMENT"
            approachSeller(part.Position, false)
            return
        end

        C.Noclip(true)

        if not runtime.SellerReady then
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
        and tick() - runtime.ReadyAt >= 1
        and tick() - runtime.LastSell >= H.Config.SellInterval then
            runtime.LastSell = tick()
            local trinketOnly = runtime.TrinketOnlyOnce == true
            fireSplit(trinketOnly)
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
        exact:AddLabel("EH_AlwaysSellTrinkets", {Text = "Always sell: Amulet, Goblet, Old Amulet, Old Ring, Ring (ignores filters)", DoesWrap = true})
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
    end

    print("[EndHub] trinket sell: tab classification fix loaded")
end

