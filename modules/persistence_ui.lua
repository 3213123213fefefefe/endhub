return function(H)
    local Tabs = H.UI and H.UI.Tabs
    local Options = H.UI and H.UI.Options
    local P = H.PersistenceManager
    if not Tabs or not Tabs.Interface or not P then return end

    local g = Tabs.Interface:AddRightGroupbox("PC Save / Persistence")
    g:AddLabel("EH_SaveStatus", {Text = "Save: " .. tostring(H.State.PersistenceStatus or "--"), DoesWrap = true})
    g:AddLabel("Config: EndHub/config.json", true)
    g:AddLabel("Keybinds: EndHub/keybinds.json", true)
    g:AddLabel("Seller: EndHub/seller_positions.json", true)
    g:AddLabel("Bot positions: EndHub/bot_positions.json", true)
    g:AddButton({Text = "SAVE EVERYTHING NOW", Func = function()
        P.SaveAll(true)
    end})
    g:AddButton({Text = "SAVE CURRENT POSITION AS FARM START", Func = function()
        if P.SaveCurrentPosition("FarmStart") then
            H.State.PersistenceStatus = "FARM START SAVED"
        else
            H.State.PersistenceStatus = "FARM START SAVE FAILED"
        end
    end})
    g:AddButton({Text = "TP TO SAVED FARM START", Func = function()
        local pos = P.GetPosition("FarmStart")
        if pos then
            H.Core.Teleport(pos + Vector3.new(0, 3, 0))
            H.State.PersistenceStatus = "TP -> FARM START"
        else
            H.State.PersistenceStatus = "NO FARM START SAVED"
        end
    end})
    g:AddLabel("Settings are autosaved when they change. Active automation states such as Auto Sell/Fly are not restored ON automatically after reopening, so the script never starts moving or selling by itself.", true)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                if Options and Options.EH_SaveStatus then
                    Options.EH_SaveStatus:SetText("Save: " .. tostring(H.State.PersistenceStatus or "--"))
                end
            end)
            task.wait(0.5)
        end
    end)
end
