return function(H)
    local X = {}
    H.Extras = X

    function X.PrintPauseDiagnostic()
        if H.ServerCycle and H.ServerCycle.Diagnostic then
            local text = H.ServerCycle.Diagnostic()
            print("[EndHub Pause] " .. tostring(text))
            return text
        end
        print("[EndHub Debug] server-cycle diagnostic unavailable")
        return nil
    end

    function X.PrintRuntime()
        local text = string.format(
            "running=%s | phase=%s | sale=%s | target=%s | job=%s",
            tostring(H.State.Running),
            tostring(H.State.FarmSellPhase),
            tostring(H.State.SellStatus),
            H.State.CurrentTarget and tostring(H.State.CurrentTarget.Name) or "none",
            tostring(game.JobId)
        )
        print("[EndHub Debug] " .. text)
        return text
    end

    if H.UI and H.UI.Tabs and H.UI.Tabs.Debug then
        local group = H.UI.Tabs.Debug:AddLeftGroupbox("Extras / Debug")
        group:AddButton({Text = "Print Pause Diagnostic", Func = X.PrintPauseDiagnostic})
        group:AddButton({Text = "Print Runtime State", Func = X.PrintRuntime})
    end
end
