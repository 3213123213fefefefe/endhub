return function(H)
    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}

    local saved = ENV.ENDHUB_KEYBINDS
    local Library = H.UI.Library
    local Options = H.UI.Options
    local Toggles = H.UI.Toggles
    local Left = H.UI.KeyLeft
    local Right = H.UI.KeyRight

    H.Keybinds = {Actions = {}, Updating = false}
    local K = H.Keybinds

    local function keyToName(key)
        if key == nil then return nil end
        if type(key) == "string" then
            if key == "None" or key == "NONE" or key == "" then return nil end
            return key
        end
        if key == Enum.UserInputType.MouseButton1 then return "MB1" end
        if key == Enum.UserInputType.MouseButton2 then return "MB2" end
        if key == Enum.UserInputType.MouseButton3 then return "MB3" end
        if typeof(key) == "EnumItem" then return key.Name end
        return nil
    end

    local function initialKey(id, fallback)
        local v = saved[id]
        if type(v) == "string" and v ~= "" then return v end
        return fallback or "None"
    end

    local function saveAll()
        if H.Core and H.Core.SaveKeybinds then H.Core.SaveKeybinds() end
    end

    local function clearDuplicate(action, newName)
        if not newName or K.Updating then return end
        K.Updating = true
        for _, other in ipairs(K.Actions) do
            if other ~= action and other.KeyName == newName then
                other.KeyName = nil
                saved[other.Id] = nil
                local opt = Options[other.OptionId]
                if opt and opt.SetValue then pcall(function() opt:SetValue("None") end) end
            end
        end
        K.Updating = false
    end

    local function addAction(group, id, label, fallback, callback)
        local optionId = "EH_KB_" .. id
        local action = {
            Id = id,
            Label = label,
            OptionId = optionId,
            Callback = callback,
            KeyName = keyToName(initialKey(id, fallback)),
        }
        K.Actions[#K.Actions + 1] = action

        group:AddLabel(label):AddKeyPicker(optionId, {
            Default = initialKey(id, fallback),
            Mode = "Press",
            Text = label,
            NoUI = false,
            Callback = function(value)
                if H.State.Unloaded or value == false or not H.Core.InputFocused() then return end
                task.spawn(callback)
            end,
            ChangedCallback = function(newKey)
                local name = keyToName(newKey)
                clearDuplicate(action, name)
                action.KeyName = name
                saved[id] = name
                saveAll()
            end,
        })
        return action
    end

    local function toggleUiToggle(id, fallbackValue)
        local t = Toggles[id]
        if t then t:SetValue(not t.Value) else fallbackValue() end
    end

    addAction(Left, "farm_toggle", "Trinket Bot", "F6", function()
        if H.State.Running then H.Farm.Stop() else H.Farm.Start() end
    end)

    addAction(Left, "farm_sell", "Farm -> Full -> Sell", "F8", function()
        toggleUiToggle("EH_FarmSell", function()
            H.Config.AutoFarmSell = not H.Config.AutoFarmSell
            H.State.FarmSellPhase = "FARM"
            if H.Config.AutoFarmSell then H.Sell.Stop() H.Farm.Start() else H.Sell.Stop() H.Farm.Stop() end
        end)
    end)

    addAction(Left, "auto_pickup", "Auto Pickup", "None", function()
        toggleUiToggle("EH_AutoPickup", function() H.Config.AutoPickup = not H.Config.AutoPickup end)
    end)

    addAction(Left, "bot_noclip", "Bot Noclip", "None", function()
        toggleUiToggle("EH_BotNoclip", function() H.Config.BotNoclip = not H.Config.BotNoclip end)
    end)

    addAction(Left, "fly", "Fly", "F3", function()
        toggleUiToggle("EH_Fly", function() H.Config.MovementFly = not H.Config.MovementFly end)
    end)

    addAction(Left, "movement_noclip", "Movement Noclip", "F4", function()
        toggleUiToggle("EH_Noclip", function() H.Config.MovementNoclip = not H.Config.MovementNoclip end)
    end)

    addAction(Left, "desync", "Desync (Local Visual)", "F9", function()
        toggleUiToggle("EH_Desync", function() H.Config.Desync = not H.Config.Desync end)
    end)

    addAction(Left, "auto_sell", "Auto Sell", "F12", function()
        toggleUiToggle("EH_AutoSell", function() if H.Config.AutoSell then H.Sell.Stop() else H.Sell.Start() end end)
    end)

    addAction(Left, "reset_character", "Reset Character", "None", function() H.Movement.ResetCharacter() end)
    addAction(Left, "teleport_selected", "Teleport Selected", "None", function() H.PlayerTools.TeleportSelected() end)
    addAction(Left, "spectate_selected", "Spectate Selected", "None", function() H.PlayerTools.SpectateSelected() end)

    addAction(Right, "stop_spectate", "Stop Spectate", "None", function() H.PlayerTools.StopSpectate() end)

    addAction(Right, "player_esp", "Player ESP", "F5", function()
        toggleUiToggle("EH_PlayerESP", function() H.Config.PlayerESP = not H.Config.PlayerESP end)
    end)

    addAction(Right, "npc_esp", "NPC ESP", "F11", function()
        toggleUiToggle("EH_NPCESP", function() H.Config.NPCESP = not H.Config.NPCESP end)
    end)

    addAction(Right, "show_rank", "Show Rank", "None", function()
        toggleUiToggle("EH_ShowRank", function() H.Config.ESPShowRank = not H.Config.ESPShowRank end)
    end)

    addAction(Right, "show_distance", "Show Distance", "None", function()
        toggleUiToggle("EH_ShowDistance", function() H.Config.ESPShowDistance = not H.Config.ESPShowDistance end)
    end)

    addAction(Right, "equipped_tags", "Equipped Tags", "None", function()
        toggleUiToggle("EH_EquippedTags", function() H.Config.ESPShowEquipped = not H.Config.ESPShowEquipped end)
    end)

    addAction(Right, "no_fog", "No Fog", "None", function()
        toggleUiToggle("EH_NoFog", function() H.Config.NoFog = not H.Config.NoFog end)
    end)

    addAction(Right, "fullbright", "Fullbright", "F10", function()
        toggleUiToggle("EH_Fullbright", function() H.Config.Fullbright = not H.Config.Fullbright end)
    end)

    addAction(Right, "skip_target", "Skip Target", "None", function() H.Farm.SkipTarget() end)
    addAction(Right, "reset_stats", "Reset Statistics", "None", function() H.Farm.ResetStats() end)
    addAction(Right, "unload", "Unload Script", "F7", function() H:Unload() end)

    Left:AddDivider()
    local uiInitial = initialKey("ui_toggle", "RightShift")
    local uiAction = {
        Id = "ui_toggle",
        Label = "Show / Hide UI",
        OptionId = "EH_KB_ui_toggle",
        KeyName = keyToName(uiInitial),
        Callback = function() end,
    }
    K.Actions[#K.Actions + 1] = uiAction

    Left:AddLabel("Show / Hide UI"):AddKeyPicker("EH_KB_ui_toggle", {
        Default = uiInitial,
        Mode = "Press",
        Text = "Show / Hide UI",
        NoUI = false,
        Callback = function() end,
        ChangedCallback = function(newKey)
            local name = keyToName(newKey)
            clearDuplicate(uiAction, name)
            uiAction.KeyName = name
            saved.ui_toggle = name
            if typeof(newKey) == "EnumItem" and newKey.EnumType == Enum.KeyCode then
                Library.ToggleKeybind = newKey
            elseif name and Enum.KeyCode[name] then
                Library.ToggleKeybind = Enum.KeyCode[name]
            end
            saveAll()
        end,
    })

    if type(uiInitial) == "string" and Enum.KeyCode[uiInitial] then Library.ToggleKeybind = Enum.KeyCode[uiInitial] end

    Right:AddDivider()
    Right:AddLabel("Click a key box and press a new key. Changes are saved when file I/O is available. Reusing a key clears the older duplicate bind where supported.", true)

    saveAll()
    print("[EndHub] all keybinds loaded")
end

