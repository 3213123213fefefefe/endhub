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

    BotRight:AddLabel("EH_BotStatus", {Text = "Status: IDLE"})
    BotRight:AddLabel("EH_Target", {Text = "Target: None"})
    BotRight:AddLabel("EH_TargetDistance", {Text = "Distance: --"})
    BotRight:AddLabel("EH_Capacity", {Text = "Capacity: --/--"})
    BotRight:AddLabel("EH_Trinkets", {Text = "Trinkets: 0"})
    BotRight:AddLabel("EH_Collected", {Text = "Collected: 0"})
    BotRight:AddLabel("EH_Session", {Text = "Session: 00:00"})
    BotRight:AddLabel("EH_Phase", {Text = "Phase: FARM"})
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

                if Options.EH_BotStatus then Options.EH_BotStatus:SetText("Status: " .. tostring(H.State.Status) .. " | Sell: " .. tostring(H.State.SellStatus)) end
                if Options.EH_Target then Options.EH_Target:SetText("Target: " .. (H.State.CurrentTarget and H.State.CurrentTarget.Name or "None")) end
                if Options.EH_TargetDistance then Options.EH_TargetDistance:SetText(H.State.CurrentTarget and ("Distance: " .. math.floor(H.State.TargetDistance or 0) .. " studs") or "Distance: --") end
                if Options.EH_Capacity then Options.EH_Capacity:SetText("Capacity: " .. tostring(H.State.InventoryCurrent) .. "/" .. tostring(H.State.InventoryMax)) end
                if Options.EH_Trinkets then Options.EH_Trinkets:SetText("Trinkets: " .. tostring(H.State.Detected)) end
                if Options.EH_Collected then Options.EH_Collected:SetText("Collected: " .. tostring(H.State.Collected)) end
                if Options.EH_Phase then Options.EH_Phase:SetText("Phase: " .. tostring(H.State.FarmSellPhase)) end

                local elapsed = H.Farm.SessionSeconds()
                local mins, secs = math.floor(elapsed / 60), math.floor(elapsed % 60)
                if Options.EH_Session then Options.EH_Session:SetText(string.format("Session: %02d:%02d", mins, secs)) end

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
