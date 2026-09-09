return function(H)
    H.SellerTools = {}
    local T = H.SellerTools
    local C = H.Core
    local Options = H.UI and H.UI.Options
    local Tabs = H.UI and H.UI.Tabs

    function T.ExportFixedClement()
        local seller = C.FindClement()
        local part = seller and C.NPCAnchor(seller)
        local pos = part and part.Position or C.GetSavedSeller()
        if not pos then
            H.State.SellStatus = "CAPTURE CLEMENT FIRST"
            return false
        end
        local key = tostring(game.PlaceId)
        H.Config.FixedSellerByPlace = H.Config.FixedSellerByPlace or {}
        H.Config.FixedSellerByPlace[key] = {pos.X, pos.Y, pos.Z}
        local saved = H.PersistenceManager and H.PersistenceManager.SaveConfig(true)
        local text = string.format('[EndHub Clement] PlaceId=%s | ["%s"] = {%.9g, %.9g, %.9g},',
            key, key, pos.X, pos.Y, pos.Z)
        print(text)
        if setclipboard then pcall(setclipboard, text) end
        H.State.SellStatus = saved and "FIXED CLEMENT SAVED + EXPORTED" or "CLEMENT EXPORTED; DISK SAVE FAILED"
        return true, text
    end

    local function fmt(pos)
        if not pos then return "--" end
        return string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z)
    end

    local function join(list)
        if not list or #list == 0 then return "--" end
        return table.concat(list, " | ")
    end

    function T.CaptureClement()
        local seller = C.FindClement()
        local part = seller and C.NPCAnchor(seller)
        if not part then
            H.State.SellStatus = "CLEMENT NOT STREAMED"
            return false
        end
        C.SaveSellerPosition(part.Position)
        H.State.SellStatus = "SELLER POS SAVED: " .. fmt(part.Position)
        print("[EndHub] Clement position:", fmt(part.Position))
        return true, part.Position
    end

    function T.CaptureCurrentPosition()
        local root = C.Root()
        if not root then
            H.State.SellStatus = "WAIT CHARACTER"
            return false
        end
        C.SaveSellerPosition(root.Position)
        H.State.SellStatus = "PLAYER POS SAVED AS SELLER: " .. fmt(root.Position)
        print("[EndHub] Saved current player position as Clement area:", fmt(root.Position))
        return true, root.Position
    end

    function T.TeleportSaved()
        local pos = C.GetSavedSeller()
        if not pos then
            H.State.SellStatus = "NO SAVED SELLER POS"
            return false
        end
        H.State.SellStatus = "TP TEST -> SAVED SELLER"
        return C.Teleport(pos + Vector3.new(0, 4, 0))
    end

    function T.Clear()
        if H.Config.FixedSellerByPlace then
            H.Config.FixedSellerByPlace[tostring(game.PlaceId)] = nil
            if H.PersistenceManager then H.PersistenceManager.SaveConfig(true) end
        end
        C.ClearSavedSeller()
        H.State.SellStatus = "SELLER POS CLEARED"
    end

    function T.DebugTrinkets()
        local rows = H.Sell.DebugTrinkets and H.Sell.DebugTrinkets() or {}
        print("[EndHub] ===== TRINKET SELL DEBUG =====")
        if #rows == 0 then
            print("[EndHub] No trinkets classified in inventory")
        else
            for _, row in ipairs(rows) do print("[EndHub]", row) end
        end
        H.State.SellStatus = #rows > 0 and ("TRINKET DEBUG: " .. tostring(#rows) .. " STACKS") or "TRINKET DEBUG: NONE FOUND"
        return rows
    end

    if Tabs and Tabs.Sell then
        local g = Tabs.Sell:AddRightGroupbox("Seller Position Memory")
        g:AddLabel("EH_SavedSellerExact", {Text = "Saved: --", DoesWrap = true})
        g:AddButton({Text = "CAPTURE CLEMENT POSITION", Func = function() T.CaptureClement() end})
        g:AddButton({Text = "FIX + COPY CLEMENT COORDINATES", Func = function() T.ExportFixedClement() end})
        g:AddButton({Text = "SAVE MY POSITION AS CLEMENT AREA", Func = function() T.CaptureCurrentPosition() end})
        g:AddButton({Text = "TP TO SAVED POSITION (TEST)", Func = function() T.TeleportSaved() end})
        g:AddButton({Text = "CLEAR SAVED POSITION", Func = function() T.Clear() end})
        g:AddLabel("Best method: stand beside Clement and press CAPTURE CLEMENT POSITION. If he is not detected, stand exactly at the merchant and use SAVE MY POSITION AS CLEMENT AREA. The seller uses this saved position when Clement is outside StreamingEnabled range.", true)

        local d = Tabs.Sell:AddRightGroupbox("Trinket Sell Debug")
        d:AddButton({Text = "DEBUG TRINKETS", Func = function() T.DebugTrinkets() end})
        d:AddLabel("EH_TrinketDebugSummary", {Text = "Trinkets: --", DoesWrap = true})
        d:AddLabel("This shows the trinket name, rarity, stack quantity and whether that rarity's Trinket filter is actually ON.", true)
    end

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                if Options and Options.EH_SavedSellerExact then
                    Options.EH_SavedSellerExact:SetText("Saved: " .. fmt(C.GetSavedSeller()))
                end
                if Options and Options.EH_TrinketDebugSummary and H.Sell.DebugTrinkets then
                    local rows = H.Sell.DebugTrinkets()
                    Options.EH_TrinketDebugSummary:SetText("Trinkets: " .. join(rows))
                end
            end)
            task.wait(0.75)
        end
    end)
end

