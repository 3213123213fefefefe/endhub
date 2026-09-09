return function(H)
    local UI = H.UI
    if not UI or not UI.Tabs or not UI.Tabs.Keybinds then return end
    local Library, Options, Toggles = UI.Library, UI.Options, UI.Toggles
    local left = UI.KeyLeft or UI.Tabs.Keybinds:AddLeftGroupbox("Keybinds")
    local right = UI.KeyRight or UI.Tabs.Keybinds:AddRightGroupbox("More Keybinds")
    UI.KeyLeft, UI.KeyRight = left, right

    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local saved = ENV.ENDHUB_KEYBINDS
    local actions = {}

    -- Old builds could bind Show / Hide UI as a normal action. Ignore that
    -- stale value so an old MouseButton1 binding cannot keep toggling the menu.
    saved.feature_show_ui = nil

    local function keyName(key)
        if key == nil then return nil end
        if type(key) == "string" then
            if key == "None" or key == "NONE" or key == "" then return nil end
            return key
        end
        if typeof(key) == "EnumItem" then return key.Name end
        return nil
    end

    local function addKey(group, id, text, fn)
        local sid = "feature_" .. id
        local optionId = "EH_KBF_" .. id
        local initial = saved[sid] or "None"
        local action = {Id = sid, OptionId = optionId, KeyName = keyName(initial)}
        actions[#actions + 1] = action

        group:AddLabel(text):AddKeyPicker(optionId, {
            Default = initial,
            Mode = "Press",
            Text = text,
            NoUI = false,
            Callback = function(value)
                if value == false or H.State.Unloaded or not H.Core.InputFocused() then return end
                task.spawn(fn)
            end,
            ChangedCallback = function(newKey)
                local name = keyName(newKey)
                if name then
                    for _, other in ipairs(actions) do
                        if other ~= action and other.KeyName == name then
                            other.KeyName = nil
                            saved[other.Id] = nil
                            if Options[other.OptionId] then
                                pcall(function() Options[other.OptionId]:SetValue("None") end)
                            end
                        end
                    end
                end
                action.KeyName = name
                saved[sid] = name
                if H.Core.SaveKeybinds then H.Core.SaveKeybinds() end
            end,
        })
    end

    local function flip(id, fallback)
        local toggle = Toggles[id]
        if toggle then toggle:SetValue(not toggle.Value) else fallback() end
    end

    addKey(left, "farm", "Trinket Bot", function()
        if H.State.Running then H.Farm.Stop() else H.Farm.Start() end
    end)
    addKey(left, "farm_sell", "Farm -> Full -> Sell", function()
        flip("EH_FarmSell", function() end)
    end)
    -- Fly and Movement Noclip keybinds are configured inline beside their switches.
    addKey(left, "reset_character", "Reset Character", function() H.Movement.ResetCharacter() end)
    addKey(left, "teleport_player", "Teleport Selected", function() H.PlayerTools.TeleportSelected() end)
    addKey(left, "boss", "Boss Bot", function()
        flip("EH_BossBot", function() H.Boss.Toggle() end)
    end)
    addKey(left, "mobfarm", "Mob Farm", function()
        flip("EH_MobFarmEnabled", function() H.MobFarm.Toggle() end)
    end)

    local menuInitial = saved.menu_toggle or "Insert"
    if not Enum.KeyCode[menuInitial] then menuInitial = "Insert" end
    Library.ToggleKeybind = Enum.KeyCode[menuInitial]
    left:AddLabel("Show / Hide UI"):AddKeyPicker("EH_MenuToggleKey", {
        Default = menuInitial,
        Mode = "Press",
        Text = "Show / Hide UI",
        NoUI = false,
        Callback = function() end,
        ChangedCallback = function(newKey)
            local name = keyName(newKey)
            if not name or not Enum.KeyCode[name] then name = "Insert" end
            saved.menu_toggle = name
            Library.ToggleKeybind = Enum.KeyCode[name]
            if H.Core.SaveKeybinds then H.Core.SaveKeybinds() end
        end,
    })

    addKey(right, "auto_sell", "Auto Sell", function()
        flip("EH_AutoSell", function() if H.Config.AutoSell then H.Sell.Stop() else H.Sell.Start() end end)
    end)
    addKey(right, "player_esp", "Player ESP", function()
        flip("EH_PlayerESP", function() H.Config.PlayerESP = not H.Config.PlayerESP end)
    end)
    addKey(right, "npc_esp", "NPC ESP", function()
        flip("EH_NPCESP", function() H.Config.NPCESP = not H.Config.NPCESP end)
    end)
    addKey(right, "fullbright", "Fullbright", function()
        flip("EH_Fullbright", function() H.Config.Fullbright = not H.Config.Fullbright end)
    end)
    addKey(right, "no_fog", "No Fog", function()
        flip("EH_NoFog", function() H.Config.NoFog = not H.Config.NoFog end)
    end)
    addKey(right, "skip_target", "Skip Target", function() H.Farm.SkipTarget() end)
    addKey(right, "reset_stats", "Reset Statistics", function() H.Farm.ResetStats() end)
    addKey(right, "unload", "Unload Script", function() H:Unload() end)
end
