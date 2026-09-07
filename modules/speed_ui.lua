return function(H)
    if not H.UI or not H.UI.Tabs or not H.UI.Tabs.Movement then return end
    if not H.Movement then return end

    H.Config.SpeedModifierEnabled = false

    local group = H.UI.Tabs.Movement:AddRightGroupbox("Speed Modifier")
    group:AddToggle("EH_SpeedModifierEnabled", {
        Text = "Enable speed modifier",
        Default = false,
        Callback = function(v)
            H.Movement.SetSpeedModifier(v)
        end,
    })

    group:AddLabel("The multiplier value can stay saved, but it will not activate automatically when EndHub loads.", true)
end
