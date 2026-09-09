return function(H)
    local S, runtime = H.Sell, H.Sell.Runtime
    local options = H.UI.Options
    local g = H.UI.Tabs.Sell:AddRightGroupbox("Sale diagnostics")
        g:AddButton({Text = "COPY COMMON ITEM IDENTITIES", Func = function()
            S.ExportItemIdentities()
        end})

        g:AddButton({Text = "TEST GOBLET + OLD AMULET INDIVIDUALLY", Func = function()
            S.TestRemainingIndividually()
        end})
        g:AddButton({Text = "TEST SELL SELECTED TRINKETS ONLY", Func = function()
            S.TestSellTrinketsOnly()
        end})
        g:AddButton({Text = "REFRESH TRINKET DIAGNOSTIC", Func = function()
            local lines = S.DebugTrinkets()
            H.State.SellStatus = "TRINKET DEBUG: " .. tostring(#lines) .. " STACKS"
            for _, line in ipairs(lines) do print("[EndHub Trinket] " .. line) end
        end})
        g:AddLabel("EH_TrinketFixCount", {Text = "Selected trinkets: --", DoesWrap = true})
        g:AddLabel("EH_TrinketFixDetail", {Text = "Detected: --", DoesWrap = true})

        task.spawn(function()
            while not H.State.Unloaded do
                pcall(function()
                    S.BuildSplitPayloads()
                    if options and options.EH_TrinketFixCount then
                        options.EH_TrinketFixCount:SetText(
                            "Selected trinkets: " .. tostring(runtime.SelectedTrinketItems or 0)
                            .. " items / " .. tostring(runtime.SelectedTrinketStacks or 0) .. " stacks"
                        )
                    end
                    if options and options.EH_TrinketFixDetail then
                        local first = runtime.TrinketDebug and runtime.TrinketDebug[1]
                        options.EH_TrinketFixDetail:SetText(
                            "Detected: " .. tostring(runtime.TrinketDebug and #runtime.TrinketDebug or 0)
                            .. (first and (" | " .. first) or "")
                        )
                    end
                end)
                task.wait(0.75)
            end
        end)
end
