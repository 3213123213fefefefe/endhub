return function(H)
    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}

    local saved = ENV.ENDHUB_KEYBINDS
    local Library = H.UI.Library
    local Options = H.UI.Options
    local Toggles = H.UI.Toggles
    local Group = H.UI.KeyGroup

    H.Keybinds = {
        Actions = {},
    }

    local function defaultKey(id, fallback)
        local v = saved[id]
        if type(v) == "string" and v ~= "" then
            return v
        end
        return fallback
    end

    local function keyToName(key)
        if not key then return nil end
        if key == Enum.UserInputType.MouseButton1 then return "MB1" end
        if key == Enum.UserInputType.MouseButton2 then return "MB2" end
        if key == Enum.UserInputType.MouseButton3 then return "MB3" end
        return key.Name
    end

    local function addAction(id, label, fallback, callback)
        local optionId = "EH_KB_" .. id
        local action = {
            Id = id,
            Label = label,
            OptionId = optionId,
            Callback = callback,
        }
        H.Keybinds.Actions[#H.Keybinds.Actions + 1] = action

        Group:AddLabel(label):AddKeyPicker(optionId, {
            Default = defaultKey(id, fallback),
            Mode = "Press",
            Text = label,
            NoUI = false,
            Callback = function(value)
                if H.State.Unloaded then return end
                if value == false then return end
                task.spawn(callback)
            end,
            ChangedCallback = function(newKey)
                saved[id] = keyToName(newKey)
            end,
        })

        return action
    end

    addAction("farm_toggle", "Trinket Bot", "F6", function()
        if H.State.Running then
            H.Farm.Stop()
        else
            H.Farm.Start()
        end
    end)

    addAction("farm_sell", "Farm -> Full -> Sell", "F8", function()
        local t = Toggles.EH_FarmSell
        if t then
            t:SetValue(not t.Value)
        else
            H.Config.AutoFarmSell = not H.Config.AutoFarmSell
            H.State.FarmSellPhase = "FARM"
            if H.Config.AutoFarmSell then
                H.Sell.Stop()
                H.Farm.Start()
            else
                H.Sell.Stop()
                H.Farm.Stop()
            end
        end
    end)

    addAction("fly_toggle", "Movement Fly", "F3", function()
        local t = Toggles.EH_Fly
        if t then
            t:SetValue(not t.Value)
        else
            H.Config.MovementFly = not H.Config.MovementFly
        end
    end)

    addAction("noclip_toggle", "Movement Noclip", "F4", function()
        local t = Toggles.EH_Noclip
        if t then
            t:SetValue(not t.Value)
        else
            H.Config.MovementNoclip = not H.Config.MovementNoclip
        end
    end)

    addAction("npc_esp", "NPC ESP", "F5", function()
        local t = Toggles.EH_NPCESP
        if t then
            t:SetValue(not t.Value)
        else
            H.Config.NPCESP = not H.Config.NPCESP
        end
    end)

    addAction("player_esp", "Player ESP", "None", function()
        local t = Toggles.EH_PlayerESP
        if t then
            t:SetValue(not t.Value)
        else
            H.Config.PlayerESP = not H.Config.PlayerESP
        end
    end)

    Group:AddDivider()

    local initialUiKey = defaultKey("ui_toggle", "RightShift")
    Group:AddLabel("Show / Hide UI"):AddKeyPicker("EH_KB_ui_toggle", {
        Default = initialUiKey,
        Mode = "Press",
        Text = "Show / Hide UI",
        NoUI = false,
        Callback = function() end,
        ChangedCallback = function(newKey)
            local name = keyToName(newKey)
            saved.ui_toggle = name

            if typeof(newKey) == "EnumItem" and newKey.EnumType == Enum.KeyCode then
                Library.ToggleKeybind = newKey
            end
        end,
    })

    if Enum.KeyCode[initialUiKey] then
        Library.ToggleKeybind = Enum.KeyCode[initialUiKey]
    end

    addAction("unload", "Unload Script", "F7", function()
        H:Unload()
    end)

    Group:AddDivider()
    Group:AddLabel("Click a key box and press a new key. These are Hydroxide's native key pickers, so rebinding no longer depends on the old custom Drawing input system.", true)

    H.Keybinds.GetOption = function(id)
        return Options["EH_KB_" .. tostring(id)]
    end

    print("[EndHub] Hydroxide keybinds loaded")
end
