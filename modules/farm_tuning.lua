return function(H)
    local group = H.UI.Tabs.Interface:AddLeftGroupbox("Farm tuning")
    group:AddSlider("EH_PickupDistance", {
        Text = "Pickup distance",
        Default = H.Config.PickupDistance,
        Min = 2, Max = 15, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.PickupDistance = v end,
    })

    group:AddSlider("EH_TargetHeight", {
        Text = "TP height",
        Default = H.Config.TargetHeight,
        Min = 0, Max = 10, Rounding = 1, Suffix = " studs",
        Callback = function(v) H.Config.TargetHeight = v end,
    })

    group:AddSlider("EH_PickupInterval", {
        Text = "Pickup interval",
        Default = H.Config.PickupInterval,
        Min = 0.10, Max = 1.00, Rounding = 2, Suffix = "s",
        Callback = function(v) H.Config.PickupInterval = v end,
    })

    group:AddSlider("EH_TargetTimeout", {
        Text = "Target timeout",
        Default = H.Config.TargetTimeout,
        Min = 3, Max = 30, Rounding = 0, Suffix = "s",
        Callback = function(v) H.Config.TargetTimeout = v end,
    })

end
