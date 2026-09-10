return function(H)
    local Tabs = H.UI and H.UI.Tabs
    if not Tabs or not H.Visuals then return end

    local left = Tabs.Visuals:AddLeftGroupbox("ESP")
    local right = Tabs.Visuals:AddRightGroupbox("Environment")

    left:AddToggle("EH_PlayerESP", {
        Text = "Player ESP", Default = false,
        Callback = function(v) H.Config.PlayerESP = v end,
    })
    left:AddToggle("EH_NPCESP", {
        Text = "NPC ESP", Default = false,
        Callback = function(v) H.Config.NPCESP = v end,
    })
    left:AddToggle("EH_ShowRank", {
        Text = "Show Rank", Default = H.Config.ESPShowRank,
        Callback = function(v) H.Config.ESPShowRank = v end,
    })
    left:AddToggle("EH_ShowPrestige", {
        Text = "Show Prestige", Default = H.Config.ESPShowPrestige,
        Callback = function(v) H.Config.ESPShowPrestige = v end,
    })
    left:AddToggle("EH_ShowMaxHP", {
        Text = "Show Max HP", Default = H.Config.ESPShowMaxHealth,
        Callback = function(v) H.Config.ESPShowMaxHealth = v end,
    })
    left:AddToggle("EH_ShowSanity", {
        Text = "Show Sanity", Default = H.Config.ESPShowSanity,
        Callback = function(v) H.Config.ESPShowSanity = v end,
    })
    left:AddToggle("EH_ShowDistance", {
        Text = "Show Distance", Default = H.Config.ESPShowDistance,
        Callback = function(v) H.Config.ESPShowDistance = v end,
    })
    left:AddToggle("EH_EquippedTags", {
        Text = "Equipped Tags", Default = H.Config.ESPShowEquipped,
        Callback = function(v) H.Config.ESPShowEquipped = v end,
    })

    right:AddToggle("EH_NoFog", {
        Text = "No Fog", Default = false,
        Callback = function(v) H.Config.NoFog = v end,
    })
    right:AddToggle("EH_Fullbright", {
        Text = "Fullbright", Default = false,
        Callback = function(v) H.Config.Fullbright = v end,
    })
    right:AddSlider("EH_Brightness", {
        Text = "Brightness", Default = H.Config.FullbrightBrightness,
        Min = 1, Max = 10, Rounding = 1,
        Callback = function(v) H.Config.FullbrightBrightness = v end,
    })
    right:AddSlider("EH_Ambient", {
        Text = "Ambient", Default = H.Config.FullbrightAmbient,
        Min = 0, Max = 1, Rounding = 2,
        Callback = function(v) H.Config.FullbrightAmbient = v end,
    })
    right:AddSlider("EH_ClockTime", {
        Text = "Clock time", Default = H.Config.FullbrightClockTime,
        Min = 0, Max = 24, Rounding = 1,
        Callback = function(v) H.Config.FullbrightClockTime = v end,
    })
end
