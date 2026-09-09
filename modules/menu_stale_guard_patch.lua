return function(H)
    local R = H.ServerCycle
    local C = H.Core
    local Player = H.S and H.S.Player
    if not R or not C or not Player or R.StaleMenuGuardInstalled then return end

    local originalMenuStep = R.MenuStep
    local staleSince = nil

    local function normalized(text)
        return tostring(text or ""):lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    end

    local function visible(pg, obj)
        local node = obj
        while node and node ~= pg do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node = node.Parent
        end
        return node == pg
    end

    local function hasActionableMenu()
        local pg = Player:FindFirstChild("PlayerGui")
        if not pg then return false end

        for _, obj in ipairs(pg:GetDescendants()) do
            if visible(pg, obj) and (obj:IsA("TextButton") or obj:IsA("TextLabel")) then
                local text = normalized(obj.Text)
                if text == "endure" or text == "play" or text == "resist" or text == "resistir" or text == "jogar"
                    or text:match("^slot%s*1$")
                    or text:find("current server", 1, true)
                    or text:find("servidor atual", 1, true) then
                    return true
                end
            end
        end
        return false
    end

    function R.MenuStep(...)
        local waiting = originalMenuStep(...)
        if waiting ~= true then
            staleSince = nil
            return waiting
        end

        if tostring(R.Status or "") ~= "WAIT MENU BUTTON / SLOT 1 / CURRENT SERVER" then
            staleSince = nil
            return waiting
        end

        local hum = C.Humanoid and C.Humanoid() or nil
        local root = C.Root and C.Root() or nil
        if not hum or hum.Health <= 0 or not root or hasActionableMenu() then
            staleSince = nil
            return waiting
        end

        staleSince = staleSince or tick()
        if tick() - staleSince < 2.0 then return waiting end

        -- The old menu shell can remain visible after the character is already
        -- in the world. Do not let non-actionable labels keep the farm paused.
        R.MenuEntered = true
        R.MenuClearSince = tick()
        R.CharacterPaused = false
        R.Status = "MENU STALE SHELL IGNORED | CHARACTER ACTIVE"
        H.State.ServerCycleStatus = R.Status
        print("[EndHub Menu] stale non-actionable menu shell ignored; character is active")
        staleSince = nil
        return false
    end

    R.StaleMenuGuardInstalled = true
    print("[EndHub] stale-menu guard loaded")
end
