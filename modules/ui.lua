return function(H)
    local function loadHydroxideLibrary()
        local urls = {
            "https://git.fable.bz/zyu/hydroxide/raw/branch/main/DEPENDENCIES/Library.lua",
            "https://raw.githubusercontent.com/lincoln1155/hydroxide/main/DEPENDENCIES/Library.lua",
            "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua",
        }
        local lastErr = "unknown error"
        for _, url in ipairs(urls) do
            local okHttp, source = pcall(function() return game:HttpGet(url, true) end)
            if okHttp and type(source) == "string" and #source > 1000 then
                local fn, compileErr = loadstring(source)
                if fn then
                    local okExec, result = pcall(fn)
                    if okExec and type(result) == "function" then
                        local okInit, initialized = pcall(result, nil, nil)
                        if okInit then result = initialized else lastErr = "initializer: " .. tostring(initialized) end
                    end
                    if okExec and type(result) == "table" then return result, url end
                else
                    lastErr = "compile: " .. tostring(compileErr)
                end
            else
                lastErr = "http: " .. tostring(source)
            end
        end
        error("[EndHub] failed to load UI: " .. tostring(lastErr))
    end

    local Library, librarySource = loadHydroxideLibrary()
    local Options, Toggles = Library.Options, Library.Toggles
    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = true
    Library.HideInactiveKeybinds = false
    Library.KeybindFrameEnabled = false

    local Window = Library:CreateWindow({
        Title = "EndHub",
        Footer = "Farm • Sell • Tools",
        Center = true,
        AutoShow = true,
        Resizable = true,
        ShowCustomCursor = false,
        NotifySide = "Right",
        ToggleKeybind = Enum.KeyCode.Unknown,
        Size = UDim2.fromOffset(900, 650),
    })

    H.UI = {Library = Library, Window = Window, Options = Options, Toggles = Toggles, Source = librarySource}

    -- Keep this exact order. Farm/Sell stay in the same window when Extras load.
    local Tabs = {
        Movement = Window:AddTab("Movement"),
        Players = Window:AddTab("Players"),
        Visuals = Window:AddTab("Visual"),
        Botting = Window:AddTab("Farm"),
        Sell = Window:AddTab("Sell"),
        Boss = Window:AddTab("Boss"),
        MobFarm = Window:AddTab("MobFarm"),
        Keybinds = Window:AddTab("Keybinds"),
        Interface = Window:AddTab("Config"),
        Debug = Window:AddTab("Debug"),
    }
    H.UI.Tabs = Tabs
    H.UI.KeyLeft = Tabs.Keybinds:AddLeftGroupbox("Keybinds")
    H.UI.KeyRight = Tabs.Keybinds:AddRightGroupbox("More Keybinds")

    ------------------------------------------------------------------------
    -- FARM
    ------------------------------------------------------------------------
    local BotLeft = Tabs.Botting:AddLeftGroupbox("Trinket Bot")
    local BotRight = Tabs.Botting:AddRightGroupbox("Status")

    BotLeft:AddButton({Text = "Start Trinket Bot", Func = function() H.ServerCycle.Start() end})
    BotLeft:AddButton({Text = "Pause Trinket Bot", Func = function() H.ServerCycle.Stop() end})
    BotLeft:AddToggle("EH_AutoPickup", {Text = "Auto pickup", Default = H.Config.AutoPickup,
        Callback = function(v) H.Config.AutoPickup = v end})
    BotLeft:AddToggle("EH_BotNoclip", {Text = "Bot Noclip", Default = H.Config.BotNoclip,
        Callback = function(v) H.Config.BotNoclip = v end})
    BotLeft:AddToggle("EH_FarmSell", {
        Text = "Farm -> Full -> Sell -> Resume",
        Default = H.Config.AutoFarmSell,
        Callback = function(v)
            if H.ServerCycle and H.ServerCycle.SyncingUI then return end
            H.Config.AutoFarmSell = v
            H.State.FarmSellPhase = "FARM"
            if v then H.Sell.Stop() H.Farm.Start() else H.Sell.Stop() H.Farm.Stop() end
        end,
    })
    BotLeft:AddSlider("EH_SellAt", {Text = "Sell at capacity", Default = H.Config.SellAtPercent,
        Min = 50, Max = 100, Rounding = 0, Suffix = "%", Callback = function(v) H.Config.SellAtPercent = v end})
    BotLeft:AddSlider("EH_ResumeAt", {Text = "Resume farm at", Default = H.Config.ResumeAtPercent,
        Min = 1, Max = 99, Rounding = 0, Suffix = "%", Callback = function(v) H.Config.ResumeAtPercent = v end})

    local lootLabels = {}
    for _, row in ipairs({
        {"EH_BotStatus", "Coleta: parado"}, {"EH_Phase", "Fase: --"},
        {"EH_Target", "Alvo: nenhum"}, {"EH_Capacity", "Inventario: --"},
        {"EH_Collected", "Coletados nesta sessao: 0"}, {"EH_LootRoute", "Rota: --"},
        {"EH_LootFilters", "Filtros: --"}, {"EH_LootSell", "Venda: --"},
        {"EH_Session", "Sessao: 00:00"},
    }) do
        lootLabels[row[1]] = BotRight:AddLabel(row[1], {Text = row[2], DoesWrap = true})
    end
    local function lootText(id, text)
        local label = lootLabels[id]
        if not label or type(label.SetText) ~= "function" then label = Options[id] end
        if label and type(label.SetText) == "function" then label:SetText(text) end
    end
    local function updateLootStatus()
        local runtime = H.Sell and H.Sell.Runtime or {}
        local selling = H.Config.AutoSell or runtime.SaleBusy or runtime.OneShot
            or (H.Config.AutoFarmSell and H.State.FarmSellPhase == "SELL")
        local running = H.State.Running and not selling
        local target = running and H.State.CurrentTarget or nil
        if target and (not target.Parent or not H.Farm.Allowed(target)) then target = nil end
        lootText("EH_Phase", "Fase: " .. (selling and "VENDA / RETORNO" or (running and "COLETA" or "PARADO")))
        lootText("EH_BotStatus", "Coleta: " .. (running and tostring(H.State.Status) or "pausada"))
        lootText("EH_Target", "Alvo: " .. (target and H.Farm.LootName(target) or "nenhum"))
        local current, maximum = H.Core.ReadCapacity()
        local capacity = "--"
        if current and maximum and maximum > 0 then capacity = string.format("%d/%d (%.1f%%)", current, maximum, current / maximum * 100) end
        lootText("EH_Capacity", "Inventario: " .. capacity)
        lootText("EH_Collected", "Coletados nesta sessao: " .. tostring(H.State.Collected or 0))
        local route = H.GetTrinketRouteStatus and H.GetTrinketRouteStatus()
        local routeText = "desativada"
        if H.Config.TrinketExplore then
            if not route or route.Total == 0 then routeText = "sem pontos salvos"
            else routeText = string.format("ponto %d/%d", route.Index, route.Total) end
        end
        lootText("EH_LootRoute", "Rota: " .. routeText)
        local rarities = {}
        for name, enabled in pairs(H.Config.PickupRarities or {}) do if enabled then rarities[#rarities + 1] = name end end
        table.sort(rarities)
        local filter = H.Config.PickupRarityFilter and (#rarities > 0 and table.concat(rarities, ", ") or "nenhuma") or "todas"
        lootText("EH_LootFilters", "Raridades: " .. filter .. " | Nome: " .. (H.Config.LootFilterEnabled and "ON" or "OFF"))
        lootText("EH_LootSell", "Venda: " .. tostring(H.State.SellStatus or "IDLE"))
        local elapsed = H.Farm.SessionSeconds()
        lootText("EH_Session", string.format("Sessao: %02d:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60)))
    end
    BotRight:AddDivider()
    BotRight:AddButton({Text = "Skip Current Target", Func = function() H.Farm.SkipTarget() end})
    BotRight:AddButton({Text = "Reset Statistics", Func = function() H.Farm.ResetStats() end})

    ------------------------------------------------------------------------
    -- SELL
    ------------------------------------------------------------------------
    local SellLeft = Tabs.Sell:AddLeftGroupbox("Common -> Epic")
    local SellRight = Tabs.Sell:AddRightGroupbox("Legendary -> Unknown")
    local function selectedFor(rarity)
        local value = {}
        for _, category in ipairs(H.SellCategories) do if H.Sell.GetFilter(rarity, category) then value[category] = true end end
        return value
    end
    local function addRarityDropdown(group, rarity)
        local id = "EH_Sell_" .. rarity
        group:AddDropdown(id, {Text = string.upper(rarity), Values = H.SellCategories, Multi = true,
            Searchable = false, MaxVisibleDropdownItems = 9,
            Callback = function(value)
                value = type(value) == "table" and value or {}
                for _, category in ipairs(H.SellCategories) do H.Sell.SetFilter(rarity, category, value[category] == true) end
            end})
        if Options[id] then Options[id]:SetValue(selectedFor(rarity)) end
    end
    for _, r in ipairs({"Common","Uncommon","Rare","Epic"}) do addRarityDropdown(SellLeft, r) end
    for _, r in ipairs({"Legendary","Mythic","Exotic","Unknown"}) do addRarityDropdown(SellRight, r) end

    local SellerLeft = Tabs.Sell:AddLeftGroupbox("Clement, Merchant")
    local SellerRight = Tabs.Sell:AddRightGroupbox("Seller Status")
    SellerLeft:AddToggle("EH_AutoSell", {Text = "Auto Sell", Default = H.Config.AutoSell,
        Callback = function(v) if v then H.Sell.Start() else H.Sell.Stop() end end})
    SellerLeft:AddButton({Text = "SELL MATCHING NOW", Func = function() H.Sell.SellMatching() end})
    SellerLeft:AddButton({Text = "Interact With Clement", Func = function() H.Sell.InteractWithClement() end})
    SellerLeft:AddButton({Text = "Save Clement Position", Func = function()
        local seller = H.Core.FindClement()
        local part = seller and H.Core.NPCAnchor(seller)
        if part then H.Core.SaveSellerPosition(part.Position) H.State.SellStatus = "SELLER POS SAVED" end
    end})
    SellerLeft:AddButton({Text = "Clear Clement Position", Func = function()
        H.Core.ClearSavedSeller() H.State.SellStatus = "SELLER POS CLEARED"
    end})
    SellerLeft:AddButton({Text = "Clear Sell Filters", Func = function()
        H.Sell.ClearFilters()
        for _, rarity in ipairs(H.SellRarities) do
            local id = "EH_Sell_" .. rarity
            if Options[id] then Options[id]:SetValue({}) end
        end
    end})
    SellerLeft:AddSlider("EH_SellRange", {Text = "Interact range", Default = H.Config.SellerInteractDistance,
        Min = 2, Max = 15, Rounding = 1, Suffix = " studs", Callback = function(v) H.Config.SellerInteractDistance = v end})
    SellerLeft:AddSlider("EH_SellInterval", {Text = "Sell interval", Default = H.Config.SellInterval,
        Min = 0.2, Max = 3, Rounding = 2, Suffix = "s", Callback = function(v) H.Config.SellInterval = v end})
    SellerRight:AddLabel("EH_SellStatus", {Text = "Status: IDLE", DoesWrap = true})
    SellerRight:AddLabel("EH_SellerCache", {Text = "Seller pos: --", DoesWrap = true})
    SellerRight:AddLabel("EH_SellerStream", {Text = "Clement: --", DoesWrap = true})
    SellerRight:AddLabel("EH_LastSell", {Text = "Last sell: 0 items / 0 stacks", DoesWrap = true})

    ------------------------------------------------------------------------
    -- CONFIG / DEBUG
    ------------------------------------------------------------------------
    local settings = Tabs.Interface:AddLeftGroupbox("Session")
    settings:AddButton({Text = "Save Settings", Func = function() H.PersistenceManager.SaveAll(true) end})
    settings:AddButton({Text = "Hide Window", Func = function() Library:Toggle(false) end})
    settings:AddButton({Text = "Unload EndHub", Func = function() H:Unload() end})
    settings:AddLabel("Profile: " .. H.Persistence.Dir, true)

    local debug = Tabs.Debug:AddRightGroupbox("Runtime")
    debug:AddButton({Text = "Print Pause Diagnostic", Func = function()
        if H.ServerCycle and H.ServerCycle.Diagnostic then print("[EndHub Pause] " .. H.ServerCycle.Diagnostic()) end
    end})

    task.spawn(function()
        while not H.State.Unloaded and not Library.Unloaded do
            pcall(function()
                updateLootStatus()
                if Options.EH_SellStatus then Options.EH_SellStatus:SetText("Status: " .. tostring(H.State.SellStatus)) end
            end)
            task.wait(0.75)
        end
    end)
    print("[EndHub] unified main UI loaded")
end
