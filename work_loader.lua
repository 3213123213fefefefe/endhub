-- AutoExecute and the teleport queue may both run this entrypoint. Claim the
-- job before the first yield, and reuse the live instance on repeated execution.
local bootEnv = getgenv()
local bootJob = tostring(game.JobId)
local buildVersion = "menu-server-5"
local existingBoot = bootEnv.ENDHUB_BOOT
if existingBoot and existingBoot.JobId == bootJob and existingBoot.Loading then
    return existingBoot.Hub or bootEnv.ENDHUB
end
local existingHub = bootEnv.ENDHUB
if existingHub and existingHub.JobId == bootJob and existingHub.State
    and existingHub.State.Ready and not existingHub.State.Unloaded
    and existingHub.WorkBuild == buildVersion and existingHub.ServerCycle
    and type(existingHub.ServerCycle.MenuStep) == "function" then
    return existingHub
end
if existingHub and existingHub.Unload then
    pcall(function() existingHub:Unload() end)
end
local boot = {JobId = bootJob, Loading = true}
bootEnv.ENDHUB_BOOT = boot
bootEnv.ENDHUB_WORK_LOADING = true
local function buildWork()
while not game:IsLoaded() or not game:GetService("Players").LocalPlayer do task.wait(0.1) end
local lootStatusModule = [=========[
return function(H)
    local ENV = getgenv()

    local function loadHydroxideLibrary()
        local urls = {
            "https://git.fable.bz/zyu/hydroxide/raw/branch/main/DEPENDENCIES/Library.lua",
            "https://raw.githubusercontent.com/lincoln1155/hydroxide/main/DEPENDENCIES/Library.lua",
            "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua",
        }

        local lastErr = "unknown error"
        for _, url in ipairs(urls) do
            local okHttp, source = pcall(function()
                return game:HttpGet(url, true)
            end)

            if okHttp and type(source) == "string" and #source > 1000 then
                local fn, compileErr = loadstring(source)
                if fn then
                    local okExec, result = pcall(fn)
                    if okExec and type(result) == "function" then
                        local okInit, initialized = pcall(result, nil, nil)
                        if okInit then result = initialized else lastErr = "initializer: " .. tostring(initialized) end
                    end
                    if okExec and type(result) == "table" then
                        return result, url
                    end
                    if type(result) ~= "table" then lastErr = "unexpected result: " .. typeof(result) .. " | " .. tostring(result) end
                else
                    lastErr = "compile: " .. tostring(compileErr)
                end
            else
                lastErr = "http: " .. tostring(source)
            end
        end
        error("[EndHub] failed to load Hydroxide Library: " .. tostring(lastErr))
    end

    local Library, librarySource = loadHydroxideLibrary()
    local Options = Library.Options
    local Toggles = Library.Toggles

    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = true
    Library.HideInactiveKeybinds = false
    Library.KeybindFrameEnabled = false

    local uiToggleKey = Enum.KeyCode.RightShift
    local savedUi = ENV.ENDHUB_KEYBINDS and ENV.ENDHUB_KEYBINDS.ui_toggle
    if type(savedUi) == "string" and Enum.KeyCode[savedUi] then uiToggleKey = Enum.KeyCode[savedUi] end

    local Window = Library:CreateWindow({
        Title = "EndHub | Fable",
        Footer = "Hydroxide UI Edition",
        Center = true,
        AutoShow = true,
        Resizable = true,
        ShowCustomCursor = true,
        NotifySide = "Right",
        ToggleKeybind = uiToggleKey,
        Size = UDim2.fromOffset(760, 620),
    })

    H.UI = {
        Library = Library,
        Window = Window,
        Options = Options,
        Toggles = Toggles,
        Source = librarySource,
    }

    local Tabs = {
        Botting = Window:AddTab("Botting"),
        Sell = Window:AddTab("Sell"),
        Movement = Window:AddTab("Movement"),
        Players = Window:AddTab("Players"),
        Visuals = Window:AddTab("Visuals"),
        Keybinds = Window:AddTab("Keybinds"),
        Interface = Window:AddTab("Interface"),
    }
    H.UI.Tabs = Tabs

    ------------------------------------------------------------------------
    -- BOTTING
    ------------------------------------------------------------------------
    local BotLeft = Tabs.Botting:AddLeftGroupbox("Trinket Bot")
    local BotRight = Tabs.Botting:AddRightGroupbox("Status")

    BotLeft:AddButton({Text = "Start Trinket Bot", Func = function() H.Farm.Start() end})
    BotLeft:AddButton({Text = "Pause Trinket Bot", Func = function() H.Farm.Stop() end})

    BotLeft:AddToggle("EH_AutoPickup", {
        Text = "Auto Pickup [E]",
        Default = H.Config.AutoPickup,
        Callback = function(v) H.Config.AutoPickup = v end,
    })

    BotLeft:AddToggle("EH_BotNoclip", {
        Text = "Bot Noclip",
        Default = H.Config.BotNoclip,
        Callback = function(v) H.Config.BotNoclip = v end,
    })

    BotLeft:AddToggle("EH_FarmSell", {
        Text = "Farm -> Full -> Sell -> Resume",
        Default = H.Config.AutoFarmSell,
        Callback = function(v)
            if H.ServerCycle and H.ServerCycle.SyncingUI then return end
            H.Config.AutoFarmSell = v
            H.State.FarmSellPhase = "FARM"
            if v then
                H.Sell.Stop()
                H.Farm.Start()
            else
                H.Sell.Stop()
                H.Farm.Stop()
            end
        end,
    })

    BotLeft:AddSlider("EH_PickupDistance", {
        Text = "Pickup distance",
        Default = H.Config.PickupDistance,
        Min = 2, Max = 15, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.PickupDistance = v end,
    })

    BotLeft:AddSlider("EH_TargetHeight", {
        Text = "TP height",
        Default = H.Config.TargetHeight,
        Min = 0, Max = 10, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.TargetHeight = v end,
    })

    BotLeft:AddSlider("EH_PickupInterval", {
        Text = "E interval",
        Default = H.Config.PickupInterval,
        Min = 0.10, Max = 1.00, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.PickupInterval = v end,
    })

    BotLeft:AddSlider("EH_TargetTimeout", {
        Text = "Target timeout",
        Default = H.Config.TargetTimeout,
        Min = 3, Max = 30, Rounding = 0, Suffix = "s",
        Callback = function(v) H.Config.TargetTimeout = v end,
    })

    BotLeft:AddSlider("EH_SellAt", {
        Text = "Sell at capacity",
        Default = H.Config.SellAtPercent,
        Min = 50, Max = 100, Rounding = 0, Suffix = "%",
        Callback = function(v) H.Config.SellAtPercent = v end,
    })

    BotLeft:AddSlider("EH_ResumeAt", {
        Text = "Resume farm at",
        Default = H.Config.ResumeAtPercent,
        Min = 1, Max = 99, Rounding = 0, Suffix = "%",
        Callback = function(v) H.Config.ResumeAtPercent = v end,
    })

    local lootLabels = {}
    for _, row in ipairs({
        {"EH_BotStatus", "Coleta: parado"},
        {"EH_Phase", "Fase: --"},
        {"EH_Target", "Alvo: nenhum"},
        {"EH_LootRarity", "Raridade: --"},
        {"EH_TargetDistance", "Distancia do alvo: --"},
        {"EH_Capacity", "Inventario: --"},
        {"EH_Trinkets", "Drops permitidos detectados: 0"},
        {"EH_Collected", "Coletados nesta sessao: 0"},
        {"EH_LootRoute", "Rota: --"},
        {"EH_LootFilters", "Filtros: --"},
        {"EH_LootSell", "Venda: --"},
        {"EH_LootSold", "Unidades removidas na ultima venda: 0"},
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
        local phase = selling and "VENDA / RETORNO" or (running and "COLETA" or "PARADO")
        lootText("EH_Phase", "Fase: " .. phase)
        lootText("EH_BotStatus", "Coleta: " .. (running and tostring(H.State.Status) or "pausada"))
        lootText("EH_Target", "Alvo: " .. (target and H.Farm.LootName(target) or "nenhum"))
        local rarity = target and H.TrinketRarity and H.TrinketRarity.Read(target) or "--"
        lootText("EH_LootRarity", "Raridade: " .. rarity)
        local root = H.Core.Root()
        local part = target and H.Core.DropPart(target)
        local distance = root and part and (root.Position - part.Position).Magnitude
        lootText("EH_TargetDistance", "Distancia do alvo: " .. (distance and string.format("%.1f studs", distance) or "--"))
        local current, maximum = H.Core.ReadCapacity()
        local capacity = "--"
        if current and maximum and maximum > 0 then capacity = string.format("%d/%d (%.1f%%)", current, maximum, current / maximum * 100) end
        lootText("EH_Capacity", "Inventario: " .. capacity)
        lootText("EH_Trinkets", "Drops permitidos detectados: " .. tostring(H.State.Detected or 0))
        lootText("EH_Collected", "Coletados nesta sessao: " .. tostring(H.State.Collected or 0))
        local route = H.GetTrinketRouteStatus and H.GetTrinketRouteStatus()
        local routeText = "desativada"
        if H.Config.TrinketExplore then
            if not route or route.Total == 0 then routeText = "sem pontos salvos"
            else
                routeText = string.format("ponto %d/%d", route.Index, route.Total)
                if running and route.Remaining > 0 then routeText = routeText .. string.format(" | espera %.1fs", route.Remaining) end
            end
        end
        lootText("EH_LootRoute", "Rota: " .. routeText)
        local rarities = {}
        for name, enabled in pairs(H.Config.PickupRarities or {}) do if enabled then rarities[#rarities + 1] = name end end
        table.sort(rarities)
        local filter = H.Config.PickupRarityFilter and (#rarities > 0 and table.concat(rarities, ", ") or "nenhuma selecionada") or "todas"
        lootText("EH_LootFilters", "Raridades: " .. filter .. " | Filtro por nome: " .. (H.Config.LootFilterEnabled and "ON" or "OFF"))
        lootText("EH_LootSell", "Venda: " .. tostring(H.State.SellStatus or "IDLE"))
        lootText("EH_LootSold", "Unidades removidas na ultima venda: " .. tostring(runtime.LastSold or 0))
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
        for _, category in ipairs(H.SellCategories) do
            if H.Sell.GetFilter(rarity, category) then value[category] = true end
        end
        return value
    end

    local function addRarityDropdown(group, rarity)
        local id = "EH_Sell_" .. rarity
        group:AddDropdown(id, {
            Text = string.upper(rarity),
            Values = H.SellCategories,
            Multi = true,
            Searchable = false,
            MaxVisibleDropdownItems = 9,
            Callback = function(value)
                value = type(value) == "table" and value or {}
                for _, category in ipairs(H.SellCategories) do
                    H.Sell.SetFilter(rarity, category, value[category] == true)
                end
            end,
        })
        if Options[id] then Options[id]:SetValue(selectedFor(rarity)) end
    end

    addRarityDropdown(SellLeft, "Common")
    addRarityDropdown(SellLeft, "Uncommon")
    addRarityDropdown(SellLeft, "Rare")
    addRarityDropdown(SellLeft, "Epic")
    addRarityDropdown(SellRight, "Legendary")
    addRarityDropdown(SellRight, "Mythic")
    addRarityDropdown(SellRight, "Exotic")
    addRarityDropdown(SellRight, "Unknown")

    local SellerLeft = Tabs.Sell:AddLeftGroupbox("Clement, Merchant")
    local SellerRight = Tabs.Sell:AddRightGroupbox("Seller Status")

    SellerLeft:AddToggle("EH_AutoSell", {
        Text = "Auto Sell",
        Default = H.Config.AutoSell,
        Callback = function(v) if v then H.Sell.Start() else H.Sell.Stop() end end,
    })

    SellerLeft:AddButton({Text = "SELL MATCHING NOW", Func = function() H.Sell.SellMatching() end})
    SellerLeft:AddButton({Text = "Interact With Clement", Func = function() H.Sell.InteractWithClement() end})
    SellerLeft:AddButton({Text = "Save Clement Position Now", Func = function()
        local seller = H.Core.FindClement()
        local part = seller and H.Core.NPCAnchor(seller)
        if part then H.Core.SaveSellerPosition(part.Position) H.State.SellStatus = "SELLER POS SAVED" end
    end})
    SellerLeft:AddButton({Text = "Clear Saved Clement Position", Func = function()
        H.Core.ClearSavedSeller()
        H.State.SellStatus = "SELLER POS CLEARED"
    end})
    SellerLeft:AddButton({Text = "Clear All Sell Filters", Func = function()
        H.Sell.ClearFilters()
        for _, rarity in ipairs(H.SellRarities) do
            local id = "EH_Sell_" .. rarity
            if Options[id] then Options[id]:SetValue({}) end
        end
    end})

    SellerLeft:AddSlider("EH_SellRange", {
        Text = "Interact range",
        Default = H.Config.SellerInteractDistance,
        Min = 2, Max = 15, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.SellerInteractDistance = v end,
    })

    SellerLeft:AddSlider("EH_SellInterval", {
        Text = "Sell interval",
        Default = H.Config.SellInterval,
        Min = 0.2, Max = 3, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.SellInterval = v end,
    })

    SellerRight:AddLabel("EH_SellStatus", {Text = "Status: IDLE", DoesWrap = true})
    SellerRight:AddLabel("EH_SellerCache", {Text = "Seller pos: --", DoesWrap = true})
    SellerRight:AddLabel("EH_SellerStream", {Text = "Clement: --", DoesWrap = true})
    SellerRight:AddLabel("EH_LastSell", {Text = "Last sell: 0 items / 0 stacks", DoesWrap = true})
    SellerRight:AddDivider()
    SellerRight:AddLabel("Each rarity is independent. Open COMMON, RARE, LEGENDARY, etc. and select exactly Weapon, Item, Trinket, Accessory, Potion, Outfit, Tome, Summon and/or Gem.", true)

    ------------------------------------------------------------------------
    -- MOVEMENT
    ------------------------------------------------------------------------
    local MoveLeft = Tabs.Movement:AddLeftGroupbox("Movement")
    local MoveRight = Tabs.Movement:AddRightGroupbox("Settings")

    MoveLeft:AddToggle("EH_Fly", {
        Text = "Fly",
        Default = H.Config.MovementFly,
        Callback = function(v) H.Config.MovementFly = v end,
    })
    MoveLeft:AddToggle("EH_Noclip", {
        Text = "Noclip",
        Default = H.Config.MovementNoclip,
        Callback = function(v)
            H.Config.MovementNoclip = v
            if not v and not H.State.Running then H.Core.Noclip(false) end
        end,
    })
    MoveLeft:AddToggle("EH_Desync", {
        Text = "Desync (Local Visual)",
        Default = H.Config.Desync,
        Callback = function(v) H.Config.Desync = v end,
    })
    MoveLeft:AddButton({Text = "Stop Fly", Func = function()
        H.Movement.StopFly()
        if Toggles.EH_Fly then Toggles.EH_Fly:SetValue(false) end
    end})
    MoveLeft:AddButton({Text = "Reset Character", Func = function() H.Movement.ResetCharacter() end})
    MoveLeft:AddLabel("Fly controls: WASD / Space / LeftCtrl", true)
    MoveLeft:AddLabel("Desync here is only a local visual camera jitter; it does not alter networking or server validation.", true)

    MoveRight:AddSlider("EH_FlySpeed", {
        Text = "Fly speed",
        Default = H.Config.MovementFlySpeed,
        Min = 20, Max = 400, Rounding = 0,
        Callback = function(v) H.Config.MovementFlySpeed = v end,
    })
    MoveRight:AddSlider("EH_WalkSpeed", {
        Text = "Base walk speed",
        Default = H.Config.WalkSpeed,
        Min = 16, Max = 100, Rounding = 0,
        Callback = function(v) H.Config.WalkSpeed = v end,
    })
    MoveRight:AddSlider("EH_SpeedMultiplier", {
        Text = "Speed multiplier",
        Default = H.Config.SpeedMultiplier,
        Min = 1, Max = 5, Rounding = 1, Suffix = "x",
        Callback = function(v) H.Config.SpeedMultiplier = v end,
    })
    MoveRight:AddSlider("EH_DesyncOffset", {
        Text = "Desync offset",
        Default = H.Config.DesyncOffset,
        Min = 0.5, Max = 8, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.DesyncOffset = v end,
    })
    MoveRight:AddSlider("EH_DesyncRate", {
        Text = "Desync rate",
        Default = H.Config.DesyncRate,
        Min = 1, Max = 30, Rounding = 0, Suffix = " Hz",
        Callback = function(v) H.Config.DesyncRate = v end,
    })

    ------------------------------------------------------------------------
    -- PLAYERS
    ------------------------------------------------------------------------
    local PlayersLeft = Tabs.Players:AddLeftGroupbox("Player Selection")
    local PlayersRight = Tabs.Players:AddRightGroupbox("Selected Player")

    local initialNames = H.PlayerTools.Names()
    if #initialNames == 0 then initialNames = {"None"} end
    PlayersLeft:AddDropdown("EH_PlayerSelect", {
        Text = "Select player",
        Values = initialNames,
        Multi = false,
        Searchable = true,
        Callback = function(value)
            if value == "None" then H.PlayerTools.Select(nil) else H.PlayerTools.Select(value) end
        end,
    })
    PlayersLeft:AddButton({Text = "Refresh Players", Func = function()
        local names = H.PlayerTools.Names()
        if #names == 0 then names = {"None"} end
        if Options.EH_PlayerSelect then Options.EH_PlayerSelect:SetValues(names) end
    end})
    PlayersLeft:AddButton({Text = "Teleport To Selected", Func = function() H.PlayerTools.TeleportSelected() end})
    PlayersLeft:AddButton({Text = "Spectate Selected", Func = function() H.PlayerTools.SpectateSelected() end})
    PlayersLeft:AddButton({Text = "Stop Spectate", Func = function() H.PlayerTools.StopSpectate() end})

    PlayersRight:AddLabel("EH_PlayerName", {Text = "Name: None"})
    PlayersRight:AddLabel("EH_PlayerRank", {Text = "Rank: N/A"})
    PlayersRight:AddLabel("EH_PlayerDistance", {Text = "Distance: --"})
    PlayersRight:AddLabel("EH_PlayerHealth", {Text = "HP: --"})
    PlayersRight:AddLabel("EH_PlayerEquipped", {Text = "Equipped: None", DoesWrap = true})
    PlayersRight:AddLabel("EH_SpectateStatus", {Text = "Spectating: OFF"})

    ------------------------------------------------------------------------
    -- VISUALS
    ------------------------------------------------------------------------
    local VisualLeft = Tabs.Visuals:AddLeftGroupbox("ESP")
    local VisualRight = Tabs.Visuals:AddRightGroupbox("Environment")

    VisualLeft:AddToggle("EH_PlayerESP", {
        Text = "Player ESP",
        Default = H.Config.PlayerESP,
        Callback = function(v) H.Config.PlayerESP = v end,
    })
    VisualLeft:AddToggle("EH_NPCESP", {
        Text = "NPC ESP",
        Default = H.Config.NPCESP,
        Callback = function(v) H.Config.NPCESP = v end,
    })
    VisualLeft:AddToggle("EH_ShowRank", {
        Text = "Show Rank",
        Default = H.Config.ESPShowRank,
        Callback = function(v) H.Config.ESPShowRank = v end,
    })
    VisualLeft:AddToggle("EH_ShowDistance", {
        Text = "Show Distance",
        Default = H.Config.ESPShowDistance,
        Callback = function(v) H.Config.ESPShowDistance = v end,
    })
    VisualLeft:AddToggle("EH_EquippedTags", {
        Text = "Equipped Tags",
        Default = H.Config.ESPShowEquipped,
        Callback = function(v) H.Config.ESPShowEquipped = v end,
    })

    VisualRight:AddToggle("EH_NoFog", {
        Text = "No Fog",
        Default = H.Config.NoFog,
        Callback = function(v) H.Config.NoFog = v end,
    })
    VisualRight:AddToggle("EH_Fullbright", {
        Text = "Fullbright",
        Default = H.Config.Fullbright,
        Callback = function(v) H.Config.Fullbright = v end,
    })
    VisualRight:AddSlider("EH_Brightness", {
        Text = "Brightness",
        Default = H.Config.FullbrightBrightness,
        Min = 1, Max = 10, Rounding = 1,
        Callback = function(v) H.Config.FullbrightBrightness = v end,
    })
    VisualRight:AddSlider("EH_Ambient", {
        Text = "Ambient",
        Default = H.Config.FullbrightAmbient,
        Min = 0, Max = 1, Rounding = 2,
        Callback = function(v) H.Config.FullbrightAmbient = v end,
    })
    VisualRight:AddSlider("EH_ClockTime", {
        Text = "Clock time",
        Default = H.Config.FullbrightClockTime,
        Min = 0, Max = 24, Rounding = 1,
        Callback = function(v) H.Config.FullbrightClockTime = v end,
    })

    ------------------------------------------------------------------------
    -- KEYBINDS / INTERFACE
    ------------------------------------------------------------------------
    H.UI.KeyLeft = Tabs.Keybinds:AddLeftGroupbox("Keybinds")
    H.UI.KeyRight = Tabs.Keybinds:AddRightGroupbox("More Keybinds")

    local InterfaceLeft = Tabs.Interface:AddLeftGroupbox("Window")
    local InterfaceRight = Tabs.Interface:AddRightGroupbox("Information")

    InterfaceLeft:AddToggle("EH_KeybindList", {
        Text = "Show keybind list",
        Default = false,
        Callback = function(v)
            Library.KeybindFrameEnabled = v
            if Library.UpdateKeybindFrame then Library:UpdateKeybindFrame() end
        end,
    })
    InterfaceLeft:AddButton({Text = "Hide Interface", Func = function() Library:Toggle(false) end})
    InterfaceLeft:AddButton({Text = "Unload EndHub", Func = function() H:Unload() end})
    InterfaceLeft:AddLabel("Drag the title bar to move the UI. Resize from the window edge/corner. This is the same UI library used by Hydroxide.", true)

    InterfaceRight:AddLabel("EndHub modular build", true)
    InterfaceRight:AddLabel("Trinket TP Bot + Auto Pickup", true)
    InterfaceRight:AddLabel("Auto Farm -> Full -> Clement Sell -> Resume", true)
    InterfaceRight:AddLabel("Exact rarity/category sell filters + Gems", true)
    InterfaceRight:AddLabel("Fly / Noclip / Speed / local visual Desync", true)
    InterfaceRight:AddLabel("Player + NPC ESP / Rank / Distance / Equipped", true)
    InterfaceRight:AddLabel("Teleport / Spectate / Fullbright / No Fog", true)
    InterfaceRight:AddLabel("Editable persistent keybinds", true)
    InterfaceRight:AddLabel("UI source: " .. tostring(librarySource), true)

    ------------------------------------------------------------------------
    -- STATUS LOOP
    ------------------------------------------------------------------------
    task.spawn(function()
        local lastPlayerRefresh = 0
        while not H.State.Unloaded and not Library.Unloaded do
            pcall(function()
                H.Core.ReadCapacity()

                updateLootStatus()

                local saved = H.Core.GetSavedSeller()
                if Options.EH_SellerCache then
                    Options.EH_SellerCache:SetText(saved and string.format("Seller pos: %.0f, %.0f, %.0f", saved.X, saved.Y, saved.Z) or "Seller pos: VISIT CLEMENT ONCE")
                end
                if Options.EH_SellStatus then Options.EH_SellStatus:SetText("Status: " .. tostring(H.State.SellStatus)) end
                if Options.EH_SellerStream then
                    local seller = H.Core.FindClement()
                    Options.EH_SellerStream:SetText(seller and "Clement: STREAMED / READY" or (saved and "Clement: OUT OF STREAMING | SAVED POS READY" or "Clement: NOT FOUND / NO SAVED POS"))
                end
                if Options.EH_LastSell then
                    Options.EH_LastSell:SetText("Last sell: " .. tostring(H.Sell.Runtime.LastSold or 0) .. " items / " .. tostring(H.Sell.Runtime.LastStacks or 0) .. " stacks")
                end

                local info = H.PlayerTools.Info()
                if Options.EH_PlayerName then Options.EH_PlayerName:SetText("Name: " .. tostring(info.Name)) end
                if Options.EH_PlayerRank then Options.EH_PlayerRank:SetText("Rank: " .. tostring(info.Rank)) end
                if Options.EH_PlayerDistance then Options.EH_PlayerDistance:SetText(info.Distance and info.Distance ~= math.huge and ("Distance: " .. math.floor(info.Distance) .. "m") or "Distance: --") end
                if Options.EH_PlayerHealth then Options.EH_PlayerHealth:SetText(info.Health and ("HP: " .. math.floor(info.Health)) or "HP: --") end
                if Options.EH_PlayerEquipped then Options.EH_PlayerEquipped:SetText("Equipped: " .. tostring(info.Equipped)) end
                if Options.EH_SpectateStatus then Options.EH_SpectateStatus:SetText("Spectating: " .. (H.PlayerTools.Spectating and "ON" or "OFF")) end

                if tick() - lastPlayerRefresh >= 2 then
                    lastPlayerRefresh = tick()
                    local names = H.PlayerTools.Names()
                    if #names == 0 then names = {"None"} end
                    if Options.EH_PlayerSelect and Options.EH_PlayerSelect.SetValues then Options.EH_PlayerSelect:SetValues(names) end
                end
            end)
            task.wait(0.35)
        end
    end)

    print("[EndHub] complete Hydroxide UI loaded")
end

]=========]
local bossStatusModule = [========[
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

]========]
local bossDetectionModule = [=======[
return function(H)
    local B, C = H.Boss, H.Core
    local players = H.S.Players
    local rows, cacheTime = {}, -math.huge
    local placeholder = 'SELECT A BOSS / NPC'
    H.Config.BossDetectionRange = math.clamp(tonumber(H.Config.BossDetectionRange) or 500, 25, 5000)
    local function scan(force)
        if not force and tick() - cacheTime < 1 then return end
        cacheTime = tick()
        rows = {}
        local root = C.Root()
        if not root then return end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA('Humanoid') and obj.Health > 0 then
                local model = obj.Parent
                local part = model and model:IsA('Model') and C.NPCAnchor(model)
                if part and not players:GetPlayerFromCharacter(model)
                    and (root.Position - part.Position).Magnitude <= H.Config.BossDetectionRange then
                    rows[#rows + 1] = {
                        Model = model, Humanoid = obj,
                        Key = model.Name .. ' | ' .. model:GetFullName(),
                    }
                end
            end
        end
        table.sort(rows, function(a,b) return a.Key < b.Key end)
    end
    function B.GetNPCNames()
        scan(true)
        local values, seen = {placeholder}, {}
        for _, row in ipairs(rows) do
            if not seen[row.Key] then seen[row.Key] = true values[#values + 1] = row.Key end
        end
        return values
    end
    function B.FindTarget()
        scan(false)
        local wanted = H.Config.BossTargetName
        if not wanted or wanted == placeholder or wanted == 'AUTO: Highest MaxHealth' then return nil end
        local root = C.Root()
        if not root then return nil end
        local best, distance = nil, math.huge
        for _, row in ipairs(rows) do
            local model, hum = row.Model, row.Humanoid
            if row.Key == wanted and model.Parent and hum.Health > 0 then
                local part = C.NPCAnchor(model)
                if part then
                    local d = root and (root.Position - part.Position).Magnitude or 0
                    if d <= H.Config.BossDetectionRange and d < distance then best, distance = model, d end
                end
            end
        end
        return best
    end
    local oldStart = B.Start
    function B.Start()
        local wanted = H.Config.BossTargetName
        if not wanted or wanted == placeholder or wanted == 'AUTO: Highest MaxHealth' then
            B.Stop()
            H.State.BossStatus = 'SELECT AN EXACT TARGET FIRST'
            local toggle = H.UI.Toggles.EH_BossBot
            if toggle and toggle.Value then toggle:SetValue(false) end
            print('[EndHub Boss] start blocked: select an exact target')
            return
        end
        print('[EndHub Boss] selected target=' .. wanted .. ' | weapon=' .. tostring(H.Config.BossWeaponName))
        return oldStart()
    end
    local function refresh(logRows)
        local wanted = H.Config.BossTargetName
        local values = B.GetNPCNames()
        if wanted and wanted ~= placeholder and wanted ~= 'AUTO: Highest MaxHealth' and string.find(wanted, ' | ', 1, true) then
            local present = false
            for _, value in ipairs(values) do if value == wanted then present = true break end end
            if not present then values[#values + 1] = wanted end
        else wanted = placeholder end
        local option = H.UI.Options.EH_BossTarget
        if option then option:SetValues(values) option:SetValue(wanted) end
        H.Config.BossTargetName = wanted
        if logRows then
            local root = C.Root()
            for _, row in ipairs(rows) do
                local part = C.NPCAnchor(row.Model)
                local d = root and part and math.floor((root.Position - part.Position).Magnitude) or -1
                print('[EndHub BossScan] ' .. row.Key .. ' | HP=' .. row.Humanoid.Health .. '/' .. row.Humanoid.MaxHealth .. ' | distance=' .. d)
            end
            print('[EndHub BossScan] loaded NPC candidates=' .. #rows .. ' | radius=' .. H.Config.BossDetectionRange)
        end
    end
    local group = H.UI.Tabs.Boss:AddLeftGroupbox('Exact Target Detection')
    group:AddSlider('EH_BossDetectionRange', {
        Text = 'NPC detection radius', Default = H.Config.BossDetectionRange,
        Min = 25, Max = 5000, Rounding = 0, Suffix = ' studs',
        Callback = function(value)
            H.Config.BossDetectionRange = value
            cacheTime = -math.huge
            B.Runtime.Target = nil
            B.Runtime.SafeDirection = nil
            refresh(false)
        end,
    })
    group:AddButton({Text = 'Scan loaded NPCs / write diagnostic', Func = function() refresh(true) end})
    group:AddLabel('Select the boss by name and path in Boss / NPC target. This lists loaded NPCs, not confirmed bosses. Players are excluded.', true)
    group:AddLabel('If the boss is missing, approach its arena and scan again. Identical paths select the nearest matching NPC.', true)
    refresh(false)
    print('[EndHub] explicit boss target selection loaded; highest-HP automatic targeting disabled')
end
]=======]
local trinketExploreModule = [======[
return function(H)
    local F, C, cfg = H.Farm, H.Core, H.Config
    local mapKey = tostring(game.PlaceId)
    cfg.TrinketExplore = cfg.TrinketExplore ~= false
    cfg.TrinketRoutes = type(cfg.TrinketRoutes) == 'table' and cfg.TrinketRoutes or {}
    cfg.TrinketRoutes[mapKey] = type(cfg.TrinketRoutes[mapKey]) == 'table' and cfg.TrinketRoutes[mapKey] or {}
    cfg.TrinketRouteWait = math.clamp(tonumber(cfg.TrinketRouteWait) or 1, 1, 10)
    local route = cfg.TrinketRoutes[mapKey]
    local index, waitUntil, selected = 0, 0, nil
    local waiting = false
    local streaming = false
    function H.GetTrinketRouteStatus()
        return {Index = index, Total = #route, Remaining = waiting and math.max(0, waitUntil - tick()) or 0}
    end
    local function save()
        if H.PersistenceManager and H.PersistenceManager.SaveConfig then
            local ok, result = pcall(H.PersistenceManager.SaveConfig, true)
            if not ok or result == false then
                warn('[EndHub Route] could not save route to disk')
                return false
            end
            print('[EndHub Route] saved | map=' .. mapKey .. ' | points=' .. #route)
            return true
        end
        warn('[EndHub Route] persistence unavailable')
        return false
    end
    local function reset()
        index = 0
        waitUntil = 0
        waiting = false
        F.ClearTarget()
    end
    local function labels()
        local values = {}
        for i, p in ipairs(route) do
            values[#values + 1] = string.format('%d | %.1f, %.1f, %.1f', i, p[1], p[2], p[3])
        end
        if #values == 0 then values[1] = 'No saved points' end
        return values
    end
    -- Ignore malformed saved entries rather than teleporting to invalid coordinates.
    for i = #route, 1, -1 do
        local p = route[i]
        local valid = type(p) == 'table'
        for n = 1, 3 do
            local v = valid and tonumber(p[n])
            if not v or v ~= v or math.abs(v) == math.huge then valid = false break end
            p[n] = v
        end
        if not valid then table.remove(route, i) end
    end
    local group = H.UI.Tabs.Botting:AddLeftGroupbox('Trinket Route')
    group:AddToggle('EH_TrinketExplore', {
        Text = 'Use saved search points', Default = cfg.TrinketExplore,
        Callback = function(value) cfg.TrinketExplore = value reset() end,
    })
    group:AddSlider('EH_TrinketRouteWait', {
        Text = 'Wait before looting at each point', Default = cfg.TrinketRouteWait,
        Min = 1, Max = 10, Rounding = 0, Suffix = ' s',
        Callback = function(value) cfg.TrinketRouteWait = value end,
    })
    group:AddDropdown('EH_TrinketRoutePoints', {
        Text = 'Saved points (visit order)', Values = labels(), Multi = false,
        Callback = function(value) selected = tonumber(tostring(value):match('^(%d+)')) end,
    })
    local function refresh(wanted)
        local option = H.UI.Options.EH_TrinketRoutePoints
        local values = labels()
        if option then
            option:SetValues(values)
            option:SetValue(values[math.clamp(wanted or 1, 1, #values)])
        end
    end
    local function changed(wanted)
        reset()
        refresh(wanted)
        save()
    end
    group:AddButton({Text = 'Add point at my position', Func = function()
        local root = C.Root()
        if not root then return end
        local p = root.Position
        route[#route + 1] = {p.X, p.Y, p.Z}
        changed(#route)
    end})
    group:AddButton({Text = 'Replace selected with my position', Func = function()
        local root = C.Root()
        if not root or not selected or not route[selected] then return end
        local p = root.Position
        route[selected] = {p.X, p.Y, p.Z}
        changed(selected)
    end})
    group:AddButton({Text = 'Remove selected point', Func = function()
        if not selected or not route[selected] then return end
        local i = selected
        table.remove(route, i)
        changed(i)
    end})
    group:AddButton({Text = 'Move selected earlier', Func = function()
        if not selected or selected <= 1 or not route[selected] then return end
        local i = selected
        route[i - 1], route[i] = route[i], route[i - 1]
        changed(i - 1)
    end})
    group:AddButton({Text = 'Move selected later', Func = function()
        if not selected or selected >= #route then return end
        local i = selected
        route[i + 1], route[i] = route[i], route[i + 1]
        changed(i + 1)
    end})
    group:AddButton({Text = 'Save route and wait time', Func = save})
    group:AddLabel('Points are saved per map. The cycle repeats the full route while collecting or detecting matching items; hops only after a complete empty lap.', true)
    refresh(1)
    local previousStart = F.Start
    function F.Start()
        -- Preserve the next route point across a sale and return to the collection area.
        -- A brief role check also preserves an unfinished streaming wait.
        if not waiting or tick() >= waitUntil then
            waiting = false
            waitUntil = 0
        end
        return previousStart()
    end
    local previousStep = F.Step
    function F.Step(dt)
        if H.State.Unloaded or H.State.Ready == false or not H.State.Running or cfg.AutoSell
            or (cfg.AutoFarmSell and H.State.FarmSellPhase == 'SELL') then return end
        if not cfg.TrinketExplore or #route == 0 then return previousStep(dt) end
        local root, hum = C.Root(), C.Humanoid()
        if not root or not hum or hum.Health <= 0 then return previousStep(dt) end
        if waiting then
            if tick() < waitUntil then
                H.State.Status = 'WAITING AT ROUTE POINT ' .. index
                C.Noclip(true)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                return
            end
            waiting = false
        end
        if F.Allowed(H.State.CurrentTarget) or F.Nearest() then return previousStep(dt) end
        if index == #route and H.ServerCycle and H.ServerCycle.OnLootComplete() then return end
        F.ClearTarget()
        index = index % #route + 1
        local p = route[index]
        local destination = Vector3.new(p[1], p[2], p[3])
        C.Noclip(true)
        if not C.Teleport(destination) then return end
        waiting = true
        waitUntil = tick() + cfg.TrinketRouteWait
        H.State.Status = 'ROUTE POINT ' .. index .. '/' .. #route
        print('[EndHub Route] point=' .. index .. '/' .. #route .. ' | wait=' .. cfg.TrinketRouteWait
            .. ' | position=' .. tostring(destination))
        if not streaming then
            streaming = true
            task.spawn(function()
                pcall(function() H.S.Player:RequestStreamAroundAsync(destination, 2) end)
                streaming = false
            end)
        end
    end
    print('[EndHub] saved trinket route loaded | points=' .. #route .. ' | wait=' .. cfg.TrinketRouteWait)
end
]======]
local trinketRarityModule = [=====[
return function(H)
    local C, F = H.Core, H.Farm
    assert(C and F and H.UI and H.UI.Tabs, 'EndHub: modulos necessarios indisponiveis')
    local cfg = H.Config
    local defaults = {'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Exotic', 'Elite', 'Unknown'}
    local function allRarities()
        local out = {}
        for _, rarity in ipairs(defaults) do out[rarity] = true end
        return out
    end
    cfg.TrinketESPRarities = type(cfg.TrinketESPRarities) == 'table' and cfg.TrinketESPRarities or allRarities()
    cfg.PickupRarities = type(cfg.PickupRarities) == 'table' and cfg.PickupRarities or allRarities()
    cfg.PickupRarityFilter = cfg.PickupRarityFilter == true
    cfg.TrinketESP = cfg.TrinketESP == true
    cfg.TrinketESPDistance = tonumber(cfg.TrinketESPDistance) or 2000
    local function metadata(obj)
        local value = obj:GetAttribute('Rarity')
        if type(value) == 'string' and value:match('%S') then return C.NormalizeRarity(value) end
        local child = obj:FindFirstChild('Rarity')
        if child and child:IsA('StringValue') and child.Value:match('%S') then return C.NormalizeRarity(child.Value) end
        return nil
    end
    local function rarityOf(obj)
        local direct = metadata(obj)
        if direct then return direct end
        local found
        for _, child in ipairs(obj:GetDescendants()) do
            local value = metadata(child)
            if child.Name == 'Rarity' and child:IsA('StringValue') and child.Value:match('%S') then
                value = C.NormalizeRarity(child.Value)
            end
            if value then
                if found and found ~= value then return 'Unknown' end
                found = value
            end
        end
        return found or 'Unknown'
    end
    H.TrinketRarity = {Read = rarityOf}
    local previousAllowed = F.Allowed
    function F.Allowed(obj)
        if not previousAllowed(obj) then return false end
        return not cfg.PickupRarityFilter or cfg.PickupRarities[rarityOf(obj)] == true
    end
    local function selection(value)
        local out = {}
        if type(value) == 'table' then
            for key, enabled in pairs(value) do if enabled == true then out[tostring(key)] = true end end
        end
        return out
    end
    local function rarityChoices()
        local values, seen = {}, {}
        local function add(value)
            if not seen[value] then seen[value] = true values[#values + 1] = value end
        end
        for _, value in ipairs(defaults) do add(value) end
        for value in pairs(cfg.TrinketESPRarities) do add(value) end
        for value in pairs(cfg.PickupRarities) do add(value) end
        local folder = C.DropsFolder()
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do if C.IsTrinketDrop(obj) then add(rarityOf(obj)) end end
        end
        return values
    end
    local initialESP = selection(cfg.TrinketESPRarities)
    local initialPickup = selection(cfg.PickupRarities)
    local espGroup = H.UI.Tabs.Visuals:AddRightGroupbox('Trinket ESP')
    espGroup:AddToggle('EH_TrinketESP', {
        Text = 'Trinket ESP', Default = cfg.TrinketESP,
        Callback = function(value) cfg.TrinketESP = value end,
    })
    espGroup:AddDropdown('EH_TrinketESPRarities', {
        Text = 'Rarities to show', Values = rarityChoices(), Multi = true, Searchable = true,
        Callback = function(value) cfg.TrinketESPRarities = selection(value) end,
    })
    espGroup:AddSlider('EH_TrinketESPDistance', {
        Text = 'Maximum distance', Min = 100, Max = 10000, Default = cfg.TrinketESPDistance,
        Rounding = 0, Suffix = ' studs', Callback = function(value) cfg.TrinketESPDistance = value end,
    })
    espGroup:AddLabel('Empty selection shows nothing. Unknown means no unambiguous rarity metadata.', true)
    local pickupGroup = H.UI.Tabs.Botting:AddRightGroupbox('Pickup Rarity')
    pickupGroup:AddToggle('EH_PickupRarityFilter', {
        Text = 'Only pick selected rarities', Default = cfg.PickupRarityFilter,
        Callback = function(value) cfg.PickupRarityFilter = value F.ClearTarget() end,
    })
    pickupGroup:AddDropdown('EH_PickupRarities', {
        Text = 'Rarities to pick', Values = rarityChoices(), Multi = true, Searchable = true,
        Callback = function(value) cfg.PickupRarities = selection(value) F.ClearTarget() end,
    })
    pickupGroup:AddLabel('With the filter ON, an empty selection picks nothing. The loot-name filter also applies.', true)
    cfg.TrinketESPRarities = initialESP
    cfg.PickupRarities = initialPickup
    local options = H.UI.Options
    -- Dropdown constructors may call their callback with an empty initial selection.
    local function refresh()
        local values = rarityChoices()
        for _, item in ipairs({{'EH_TrinketESPRarities', 'TrinketESPRarities'}, {'EH_PickupRarities', 'PickupRarities'}}) do
            local option = options[item[1]]
            local saved = selection(cfg[item[2]])
            if option then option:SetValues(values) option:SetValue(saved) end
        end
    end
    local function diagnose()
        refresh()
        local folder = C.DropsFolder()
        local count = 0
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if C.IsTrinketDrop(obj) then
                    count = count + 1
                    print('[EndHub Rarity] ' .. F.LootName(obj) .. ' | rarity=' .. rarityOf(obj)
                        .. ' | pickup=' .. tostring(F.Allowed(obj)))
                end
            end
        end
        print('[EndHub Rarity] drops=' .. count)
    end
    espGroup:AddButton({Text = 'Refresh rarities / log drops', Func = diagnose})
    pickupGroup:AddButton({Text = 'Refresh rarities / log drops', Func = diagnose})
    refresh()

    local colors = {
        Common = Color3.fromRGB(230,230,230), Uncommon = Color3.fromRGB(100,235,130),
        Rare = Color3.fromRGB(100,170,255), Epic = Color3.fromRGB(195,115,255),
        Legendary = Color3.fromRGB(255,195,65), Mythic = Color3.fromRGB(255,100,135),
    }
    local labels = {}
    local function remove(obj)
        local item = labels[obj]
        if item then item.Gui:Destroy() labels[obj] = nil end
    end
    local function clear()
        for obj in pairs(labels) do remove(obj) end
    end
    local function update()
        local pg = H.S.Player:FindFirstChild('PlayerGui')
        local root = C.Root()
        local folder = C.DropsFolder()
        if not cfg.TrinketESP or not pg or not root or not folder then clear() return end
        local seen = {}
        for _, obj in ipairs(folder:GetChildren()) do
            if C.IsTrinketDrop(obj) then
                local rarity = rarityOf(obj)
                local part = C.DropPart(obj)
                local distance = part and (part.Position - root.Position).Magnitude
                if part and part:IsA('BasePart') and cfg.TrinketESPRarities[rarity] == true
                    and distance <= cfg.TrinketESPDistance then
                    seen[obj] = true
                    local item = labels[obj]
                    if item and item.Gui.Parent ~= pg then remove(obj) item = nil end
                    if not item then
                        local gui = Instance.new('BillboardGui')
                        gui.Name = 'EndHub_TrinketESP'
                        gui.Size = UDim2.fromOffset(240, 48)
                        gui.StudsOffset = Vector3.new(0, 2.5, 0)
                        gui.AlwaysOnTop = true
                        gui.Parent = pg
                        local label = Instance.new('TextLabel')
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
                    item.Label.Text = F.LootName(obj) .. ' [' .. rarity .. ']\n' .. math.floor(distance) .. ' studs'
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
        local reported = false
        while not H.State.Unloaded do
            local ok, err = pcall(update)
            if not ok then
                clear()
                if not reported then warn('[EndHub Rarity] ESP error: ' .. tostring(err)) reported = true end
            else reported = false end
            task.wait(0.2)
        end
        clear()
    end)
    print('[EndHub] Trinket ESP + independent pickup rarity filter loaded')
end
]=====]
-- Versao de teste: modulo de venda local; demais modulos do GitHub.
local testSellModule = [====[
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
                            continue
                        end
                        print("[EndHub AutoSell] no eligible items after 3s recheck")
                        local blocked = 0
                        for _, attempts in pairs(failures) do if attempts >= 2 then blocked = blocked + 1 end end
                        finish(string.format("DONE: COUNT DECREASED %d | UNCHANGED %d", decreased, blocked))
                        return
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

]====]
-- Executar no lugar do loader habitual. Baixa a versao atual do GitHub.
local basePrint, baseWarn = print, warn
local compile, getEnv, setEnv = loadstring, getfenv, setfenv
local filename = 'endHub-console.txt'
assert(type(appendfile) == 'function' and type(writefile) == 'function' and type(isfile) == 'function', 'Funcoes de arquivo indisponiveis')
assert(type(getEnv) == 'function' and type(setEnv) == 'function', 'Funcoes de ambiente indisponiveis')
if not isfile(filename) then writefile(filename, '') end
appendfile(filename, '\n--- Loader GitHub com captura ' .. os.date('!%Y-%m-%dT%H:%M:%SZ') .. ' ---\n')
local env = getgenv()
if env.ENDHUB_LOG_CAPTURE then
    pcall(function() env.ENDHUB_LOG_CAPTURE:Disconnect() end)
    env.ENDHUB_LOG_CAPTURE = nil
end
local failed = false
local function record(kind, ...)
    if failed then return end
    local args = {}
    for i = 1, select('#', ...) do args[i] = tostring(select(i, ...)) end
    local message = table.concat(args, '\t')
    if not string.match(string.lower(message), '^%[endhub') then return end
    local ok, err = pcall(appendfile, filename, os.date('!%Y-%m-%dT%H:%M:%SZ') .. ' [' .. kind .. '] ' .. message .. '\n')
    if not ok then
        failed = true
        baseWarn('[EndHub Logger] Falha ao gravar: ' .. tostring(err))
    end
end
local function loggedPrint(...)
    basePrint(...)
    record('print', ...)
end
local function loggedWarn(...)
    baseWarn(...)
    record('warn', ...)
end
local wrappedCompile
wrappedCompile = function(source, chunkName)
    if string.find(source, '[EndHub] trinket sell: tab classification fix loaded', 1, true) then
        source = testSellModule
        loggedPrint('[EndHub Logger] TESTE v8: contagem real e confirmacao rapida tambem para itens empilhados')
    end
    if string.find(source, '[EndHub] boss UI loaded', 1, true) then
        source = bossStatusModule
    end
    if string.find(source, '[EndHub] complete Hydroxide UI loaded', 1, true) then
        source = lootStatusModule
    end
    local fn, err = compile(source, chunkName)
    if not fn then
        record('error', '[EndHub Logger] compilacao: ' .. tostring(err))
        return nil, err
    end
    local originalEnv = getEnv(fn)
    local scopedEnv = setmetatable({
        print = loggedPrint,
        warn = loggedWarn,
        loadstring = wrappedCompile,
    }, { __index = originalEnv, __newindex = originalEnv })
    setEnv(fn, scopedEnv)
    return fn
end
loggedPrint('[EndHub Logger] captura direta iniciada')
local ok, result = pcall(function()
    local url = 'https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/EndHub.lua?v=' .. tostring(os.time())
    local source = game:HttpGet(url)
    local fn, err = wrappedCompile(source, 'EndHub GitHub loader')
    assert(fn, err)
    local hub = fn()
    local extension, extensionError = wrappedCompile(trinketRarityModule, 'EndHub trinket rarity')
    assert(extension, extensionError)
    extension()(hub)
    local explore, exploreError = wrappedCompile(trinketExploreModule, 'EndHub exploration')
    assert(explore, exploreError)
    explore()(hub)
    local bossDetection, bossError = wrappedCompile(bossDetectionModule, 'EndHub boss detection')
    assert(bossDetection, bossError)
    bossDetection()(hub)
    -- Install last so route/sell overrides cannot bypass the player checks.
    local cycleSource = game:HttpGet(hub.Repo .. 'modules/server_cycle.lua?v=' .. tostring(os.time()))
    local cycle, cycleError = wrappedCompile(cycleSource, 'EndHub server cycle')
    assert(cycle, cycleError)
    cycle()(hub)
    hub.State.Ready = true
    return hub
end)
if not ok then
    record('error', '[EndHub Logger] erro no carregamento: ' .. tostring(result))
    error(result, 0)
end
return result
end

local bootOK, hub = pcall(function()
    local loaded = buildWork()
    assert(loaded.ServerCycle and type(loaded.ServerCycle.MenuStep) == "function",
        "[EndHub Loader] server cycle missing; initialization incomplete")
    loaded.WorkBuild = buildVersion
    bootEnv.ENDHUB = loaded
    loaded.ServerCycle.Bootstrap()
    print("[EndHub Loader] " .. buildVersion .. " | cycle=" .. tostring(loaded.ServerCycle.Status))
    return loaded
end)
bootEnv.ENDHUB_WORK_LOADING = nil
boot.Loading = false
if not bootOK then
    local partial = bootEnv.ENDHUB
    if partial then
        if partial.Unload then pcall(function() partial:Unload() end) end
        if partial.State then partial.State.Unloaded = true partial.State.Running = false end
        for _, connection in ipairs(partial.Connections or {}) do
            pcall(function() connection:Disconnect() end)
        end
        if bootEnv.ENDHUB == partial then bootEnv.ENDHUB = nil end
    end
    bootEnv.ENDHUB_BOOT = nil -- A failed download must remain retryable.
    error(hub, 0)
end
boot.Hub = hub
return hub
