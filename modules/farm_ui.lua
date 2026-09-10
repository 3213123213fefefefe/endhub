return function(H)
    if not H.UI or not H.UI.Tabs or not H.UI.Tabs.Botting or not H.Farm then return end

    local Options = H.UI.Options
    local F = H.Farm
    local MoveGroup = H.UI.Tabs.Botting:AddLeftGroupbox("Farm Movement")
    local LootGroup = H.UI.Tabs.Botting:AddRightGroupbox("Loot Selection")

    MoveGroup:AddDropdown("EH_FarmMoveMode", {
        Text = "Travel mode",
        Values = {"Tween", "Fly"},
        Default = H.Config.FarmMoveMode == "Fly" and 2 or 1,
        Multi = false,
        Callback = function(value)
            H.FarmMovement.Cancel()
            H.Config.FarmMoveMode = value == "Fly" and "Fly" or "Tween"
            H.Farm.ClearTarget()
        end,
    })

    MoveGroup:AddSlider("EH_FarmTweenSpeed", {
        Text = "Tween speed",
        Default = tonumber(H.Config.FarmTweenSpeed) or 85,
        Min = 15, Max = 250, Rounding = 0, Suffix = " studs/s",
        Callback = function(value)
            H.FarmMovement.Cancel()
            H.Config.FarmTweenSpeed = value
        end,
    })

    MoveGroup:AddSlider("EH_FarmFlySpeed", {
        Text = "Farm fly speed",
        Default = tonumber(H.Config.FarmFlySpeed) or 85,
        Min = 15, Max = 250, Rounding = 0, Suffix = " studs/s",
        Callback = function(value) H.Config.FarmFlySpeed = value end,
    })

    LootGroup:AddToggle("EH_LootFilterEnabled", {
        Text = "Only pick selected loot",
        Default = H.Config.LootFilterEnabled == true,
        Callback = function(value)
            H.Config.LootFilterEnabled = value
            H.Farm.ClearTarget()
        end,
    })

    local function visibleLootNames()
        local names = F.GetLootNames()
        if #names == 0 then return {"No loot detected"} end
        return names
    end

    local savedSelection = F.GetSelectedLoot()
    LootGroup:AddDropdown("EH_FarmLootSelection", {
        Text = "Loot to pick",
        Values = visibleLootNames(),
        Multi = true,
        Searchable = true,
        MaxVisibleDropdownItems = 12,
        Callback = function(value) F.SetLootSelection(type(value) == "table" and value or {}) end,
    })

    local function refreshLootList(keepSelection)
        local option = Options.EH_FarmLootSelection
        if option and option.SetValues then option:SetValues(visibleLootNames()) end
        if option and option.SetValue then option:SetValue(keepSelection and F.GetSelectedLoot() or {}) end
    end

    if Options.EH_FarmLootSelection and Options.EH_FarmLootSelection.SetValue then
        Options.EH_FarmLootSelection:SetValue(savedSelection)
    end

    LootGroup:AddButton({Text = "Refresh Loot List", Func = function() refreshLootList(true) end})
    LootGroup:AddButton({Text = "Select All Visible Loot", Func = function()
        local selected = F.SelectAllVisibleLoot()
        local option = Options.EH_FarmLootSelection
        if option and option.SetValues then option:SetValues(visibleLootNames()) end
        if option and option.SetValue then option:SetValue(selected) end
    end})
    LootGroup:AddButton({Text = "Clear Loot Selection", Func = function()
        F.ClearLootSelection()
        local option = Options.EH_FarmLootSelection
        if option and option.SetValue then option:SetValue({}) end
    end})

    print("[EndHub] farm movement + loot filter UI loaded")
end
