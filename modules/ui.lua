return function(H)
    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}

    local function loadHydroxideLibrary()
        local urls = {
            "https://git.fable.bz/zyu/hydroxide/raw/branch/main/DEPENDENCIES/Library.lua",
            "https://raw.githubusercontent.com/lincoln1155/hydroxide/main/DEPENDENCIES/Library.lua",
        }

        local lastErr = "unknown error"
        for _, url in ipairs(urls) do
            local okHttp, source = pcall(function()
                return game:HttpGet(url, true)
            end)

            if okHttp and type(source) == "string" and #source > 1000 then
                local fn, compileErr = loadstring(source)
                if fn then
                    local okLib, lib = pcall(fn)
                    if okLib and type(lib) == "table" then
                        return lib, url
                    end
                    lastErr = tostring(lib)
                else
                    lastErr = tostring(compileErr)
                end
            else
                lastErr = tostring(source)
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

    local savedUiKey = ENV.ENDHUB_KEYBINDS.ui_toggle
    local uiToggleKey = Enum.KeyCode.RightShift
    if type(savedUiKey) == "string" and Enum.KeyCode[savedUiKey] then
        uiToggleKey = Enum.KeyCode[savedUiKey]
    end

    local Window = Library:CreateWindow({
        Title = "EndHub | Trinket Bot",
        Footer = "Fable Edition",
        Center = true,
        AutoShow = true,
        Resizable = true,
        ShowCustomCursor = true,
        NotifySide = "Right",
        ToggleKeybind = uiToggleKey,
        Size = UDim2.fromOffset(720, 600),
    })

    H.UI = {
        Library = Library,
        Window = Window,
        Options = Options,
        Toggles = Toggles,
        Source = librarySource,
        Visible = true,
    }

    local Tabs = {
        Botting = Window:AddTab("Botting"),
        Sell = Window:AddTab("Sell"),
        Movement = Window:AddTab("Movement"),
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

    BotLeft:AddButton({
        Text = "Start Trinket Bot",
        Func = function()
            H.Farm.Start()
        end,
    })

    BotLeft:AddButton({
        Text = "Pause Trinket Bot",
        Func = function()
            H.Farm.Stop()
        end,
    })

    BotLeft:AddToggle("EH_AutoPickup", {
        Text = "Auto Pickup [E]",
        Default = H.Config.AutoPickup,
        Callback = function(v)
            H.Config.AutoPickup = v
        end,
    })

    BotLeft:AddToggle("EH_BotNoclip", {
        Text = "Bot Noclip",
        Default = H.Config.BotNoclip,
        Callback = function(v)
            H.Config.BotNoclip = v
        end,
    })

    BotLeft:AddToggle("EH_FarmSell", {
        Text = "Farm -> Full -> Sell",
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

    BotLeft:AddSlider("EH_SellAt", {
        Text = "Sell at capacity",
        Default = H.Config.SellAtPercent,
        Min = 50,
        Max = 100,
        Rounding = 0,
        Suffix = "%",
        Callback = function(v)
            H.Config.SellAtPercent = v
        end,
    })

    BotLeft:AddSlider("EH_ResumeAt", {
        Text = "Resume farm at",
        Default = H.Config.ResumeAtPercent,
        Min = 1,
        Max = 99,
        Rounding = 0,
        Suffix = "%",
        Callback = function(v)
            H.Config.ResumeAtPercent = v
        end,
    })

    BotRight:AddLabel("EH_BotStatus", {Text = "Status: IDLE"})
    BotRight:AddLabel("EH_Capacity", {Text = "Capacity: --/--"})
    BotRight:AddLabel("EH_Trinkets", {Text = "Trinkets detected: 0"})
    BotRight:AddLabel("EH_Collected", {Text = "Collected: 0"})
    BotRight:AddLabel("EH_SellerCache", {Text = "Seller pos: --", DoesWrap = true})
    BotRight:AddDivider()
    BotRight:AddLabel("The bot teleports to trinkets. When inventory is full it can teleport to the saved Clement area, wait for streaming, sell, then resume farming.", true)

    ------------------------------------------------------------------------
    -- SELL
    ------------------------------------------------------------------------
    local SellLeft = Tabs.Sell:AddLeftGroupbox("Common -> Epic")
    local SellRight = Tabs.Sell:AddRightGroupbox("Legendary -> Unknown")

    local function selectedFor(rarity)
        local value = {}
        local bucket = H.Config.SellByRarity[rarity]
        if bucket then
            for _, category in ipairs(H.SellCategories) do
                if bucket[category] then
                    value[category] = true
                end
            end
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
            Callback = function(value)
                value = type(value) == "table" and value or {}
                for _, category in ipairs(H.SellCategories) do
                    H.Sell.SetFilter(rarity, category, value[category] == true)
                end
            end,
        })

        if Options[id] then
            Options[id]:SetValue(selectedFor(rarity))
        end
    end

    addRarityDropdown(SellLeft, "Common")
    addRarityDropdown(SellLeft, "Uncommon")
    addRarityDropdown(SellLeft, "Rare")
    addRarityDropdown(SellLeft, "Epic")

    addRarityDropdown(SellRight, "Legendary")
    addRarityDropdown(SellRight, "Mythic")
    addRarityDropdown(SellRight, "Exotic")
    addRarityDropdown(SellRight, "Unknown")

    local SellControl = Tabs.Sell:AddLeftGroupbox("Seller")
    local SellInfo = Tabs.Sell:AddRightGroupbox("Sell Status")

    SellControl:AddToggle("EH_AutoSell", {
        Text = "Auto Sell",
        Default = H.Config.AutoSell,
        Callback = function(v)
            if v then
                H.Sell.Start()
            else
                H.Sell.Stop()
            end
        end,
    })

    SellControl:AddButton({
        Text = "Sell Matching Now",
        Func = function()
            H.Sell.SellMatching()
        end,
    })

    SellControl:AddButton({
        Text = "Interact With Clement",
        Func = function()
            local seller = H.Core.FindClement()
            if seller then
                H.Config.AutoSell = true
                H.Sell.Runtime.LastInteract = 0
                task.delay(1.25, function()
                    if not H.State.Unloaded and Toggles.EH_AutoSell and not Toggles.EH_AutoSell.Value then
                        H.Config.AutoSell = false
                    end
                end)
            else
                local saved = H.Core.GetSavedSeller()
                if saved then
                    H.Core.Teleport(saved + Vector3.new(0, 4, 0))
                end
            end
        end,
    })

    SellControl:AddSlider("EH_SellInterval", {
        Text = "Sell interval",
        Default = H.Config.SellInterval,
        Min = 0.2,
        Max = 3,
        Rounding = 2,
        Suffix = "s",
        Callback = function(v)
            H.Config.SellInterval = v
        end,
    })

    SellInfo:AddLabel("EH_SellStatus", {Text = "Status: IDLE", DoesWrap = true})
    SellInfo:AddLabel("EH_SellerStatus", {Text = "Clement: --", DoesWrap = true})
    SellInfo:AddLabel("EH_LastSell", {Text = "Last sell: 0 items / 0 stacks", DoesWrap = true})
    SellInfo:AddDivider()
    SellInfo:AddLabel("Each rarity above is its own multi-select dropdown. Open COMMON, RARE, etc. and tick exactly Weapon, Item, Trinket, Tome, Gem or any other category you want sold.", true)

    ------------------------------------------------------------------------
    -- MOVEMENT
    ------------------------------------------------------------------------
    local MoveLeft = Tabs.Movement:AddLeftGroupbox("Movement")
    local MoveRight = Tabs.Movement:AddRightGroupbox("Settings")

    MoveLeft:AddToggle("EH_Fly", {
        Text = "Fly",
        Default = H.Config.MovementFly,
        Callback = function(v)
            H.Config.MovementFly = v
        end,
    })

    MoveLeft:AddToggle("EH_Noclip", {
        Text = "Noclip",
        Default = H.Config.MovementNoclip,
        Callback = function(v)
            H.Config.MovementNoclip = v
            if not v then H.Core.Noclip(false) end
        end,
    })

    MoveRight:AddSlider("EH_FlySpeed", {
        Text = "Fly speed",
        Default = H.Config.MovementFlySpeed,
        Min = 10,
        Max = 250,
        Rounding = 0,
        Callback = function(v)
            H.Config.MovementFlySpeed = v
        end,
    })

    MoveRight:AddSlider("EH_WalkSpeed", {
        Text = "Walk speed",
        Default = H.Config.WalkSpeed,
        Min = 16,
        Max = 100,
        Rounding = 0,
        Callback = function(v)
            H.Config.WalkSpeed = v
        end,
    })

    ------------------------------------------------------------------------
    -- VISUALS
    ------------------------------------------------------------------------
    local VisualLeft = Tabs.Visuals:AddLeftGroupbox("ESP")
    local VisualRight = Tabs.Visuals:AddRightGroupbox("Environment")

    VisualLeft:AddToggle("EH_NPCESP", {
        Text = "NPC ESP",
        Default = H.Config.NPCESP,
        Callback = function(v)
            H.Config.NPCESP = v
        end,
    })

    VisualLeft:AddToggle("EH_PlayerESP", {
        Text = "Player ESP",
        Default = H.Config.PlayerESP,
        Callback = function(v)
            H.Config.PlayerESP = v
        end,
    })

    VisualRight:AddToggle("EH_NoFog", {
        Text = "No Fog",
        Default = H.Config.NoFog,
        Callback = function(v)
            H.Config.NoFog = v
        end,
    })

    VisualRight:AddToggle("EH_Fullbright", {
        Text = "Fullbright",
        Default = H.Config.Fullbright,
        Callback = function(v)
            H.Config.Fullbright = v
        end,
    })

    VisualRight:AddSlider("EH_Brightness", {
        Text = "Brightness",
        Default = H.Config.FullbrightBrightness,
        Min = 1,
        Max = 10,
        Rounding = 1,
        Callback = function(v)
            H.Config.FullbrightBrightness = v
        end,
    })

    VisualRight:AddSlider("EH_ClockTime", {
        Text = "Clock time",
        Default = H.Config.FullbrightClockTime,
        Min = 0,
        Max = 24,
        Rounding = 1,
        Callback = function(v)
            H.Config.FullbrightClockTime = v
        end,
    })

    ------------------------------------------------------------------------
    -- KEYBINDS / INTERFACE
    ------------------------------------------------------------------------
    H.UI.KeyGroup = Tabs.Keybinds:AddLeftGroupbox("Keybinds")
    local KeyInfo = Tabs.Keybinds:AddRightGroupbox("How to change")
    KeyInfo:AddLabel("Click the key box beside an action, then press the new key. The Hydroxide key picker handles capture directly, so you no longer need the old custom click detector.", true)
    KeyInfo:AddLabel("Backspace/Delete/Escape clears a bind where supported by the library.", true)

    local InterfaceLeft = Tabs.Interface:AddLeftGroupbox("Window")
    local InterfaceRight = Tabs.Interface:AddRightGroupbox("Script")

    InterfaceLeft:AddToggle("EH_KeybindList", {
        Text = "Show keybind list",
        Default = false,
        Callback = function(v)
            Library.KeybindFrameEnabled = v
            if Library.UpdateKeybindFrame then
                Library:UpdateKeybindFrame()
            end
        end,
    })

    InterfaceLeft:AddLabel("This is Hydroxide's actual UI library. The window is draggable and resizable; drag the title bar to move it anywhere inside Roblox.", true)
    InterfaceLeft:AddLabel("UI source: " .. tostring(librarySource), true)

    InterfaceRight:AddButton({
        Text = "Unload EndHub",
        Func = function()
            H:Unload()
        end,
    })

    ------------------------------------------------------------------------
    -- STATUS LOOP
    ------------------------------------------------------------------------
    task.spawn(function()
        while not H.State.Unloaded and not Library.Unloaded do
            pcall(function()
                H.Core.ReadCapacity()

                if Options.EH_BotStatus then
                    Options.EH_BotStatus:SetText("Status: " .. tostring(H.State.Status) .. " | Sell: " .. tostring(H.State.SellStatus))
                end
                if Options.EH_Capacity then
                    Options.EH_Capacity:SetText("Capacity: " .. tostring(H.State.InventoryCurrent) .. "/" .. tostring(H.State.InventoryMax))
                end
                if Options.EH_Trinkets then
                    Options.EH_Trinkets:SetText("Trinkets detected: " .. tostring(H.State.Detected))
                end
                if Options.EH_Collected then
                    Options.EH_Collected:SetText("Collected: " .. tostring(H.State.Collected))
                end

                local saved = H.Core.GetSavedSeller()
                if Options.EH_SellerCache then
                    if saved then
                        Options.EH_SellerCache:SetText(string.format("Seller pos: %.0f, %.0f, %.0f", saved.X, saved.Y, saved.Z))
                    else
                        Options.EH_SellerCache:SetText("Seller pos: VISIT CLEMENT ONCE")
                    end
                end

                if Options.EH_SellStatus then
                    Options.EH_SellStatus:SetText("Status: " .. tostring(H.State.SellStatus))
                end

                if Options.EH_SellerStatus then
                    local seller = H.Core.FindClement()
                    Options.EH_SellerStatus:SetText(seller and "Clement: STREAMED / READY" or (saved and "Clement: OUT OF STREAMING | SAVED POS READY" or "Clement: NOT FOUND / NO SAVED POS"))
                end

                if Options.EH_LastSell and H.Sell and H.Sell.Runtime then
                    Options.EH_LastSell:SetText("Last sell: " .. tostring(H.Sell.Runtime.LastSold or 0) .. " items / " .. tostring(H.Sell.Runtime.LastStacks or 0) .. " stacks")
                end
            end)
            task.wait(0.35)
        end
    end)

    print("[EndHub] Hydroxide UI loaded")
end
