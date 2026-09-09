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

    local uiToggleKey = Enum.KeyCode.RightControl
    local savedUi = nil
    if type(savedUi) == "string" and Enum.KeyCode[savedUi] then uiToggleKey = Enum.KeyCode[savedUi] end

    local Window = Library:CreateWindow({
        Title = "EndHub | Extras",
        Footer = "Optional tools",
        Center = true,
        AutoShow = true,
        Resizable = true,
        ShowCustomCursor = false,
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
        Movement = Window:AddTab("Movement"), Players = Window:AddTab("Players"),
        Visuals = Window:AddTab("Visuals"), Keybinds = Window:AddTab("Keybinds"),
        Sell = Window:AddTab("Diagnostics"), Interface = Window:AddTab("Settings"),
    }
    H.UI.Tabs = Tabs
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
    InterfaceLeft:AddButton({Text = "Close Extras", Func = function() H.CloseExtras() end})
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

    task.spawn(function()
        while not H.State.Unloaded and not Library.Unloaded do
            pcall(function()
                local info = H.PlayerTools.Info()
                for id, text in pairs({EH_PlayerName = "Name: " .. tostring(info.Name),
                    EH_PlayerRank = "Rank: " .. tostring(info.Rank),
                    EH_PlayerDistance = "Distance: " .. tostring(info.Distance),
                    EH_PlayerHealth = "HP: " .. tostring(info.Health),
                    EH_PlayerEquipped = "Equipped: " .. tostring(info.Equipped),
                    EH_SpectateStatus = "Spectating: " .. tostring(H.PlayerTools.Spectating)}) do
                    if Options[id] then Options[id]:SetText(text) end
                end
            end)
            task.wait(1)
        end
    end)
end
