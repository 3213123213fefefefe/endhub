return function(H)
    local R = H.ServerCycle
    if not R or R.FirstScreenPatchInstalled then return end

    local Player = H.S.Player
    local VIM = game:GetService("VirtualInputManager")
    local originalMenuStep = R.MenuStep
    local attempts = setmetatable({}, {__mode = "k"})
    local lastActivation = 0

    local function setStatus(value)
        if R.Status ~= value then print("[EndHub Cycle] " .. value) end
        R.Status = value
        H.State.ServerCycleStatus = value
    end

    local function visible(pg, obj)
        if not obj then return false end
        local node = obj
        while node and node ~= pg do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node = node.Parent
        end
        return node == pg
    end

    local function exactFirstScreenButton()
        local pg = Player:FindFirstChild("PlayerGui")
        if not pg then return nil end

        -- Exact live paths captured from this game. Prefer these over text scanning
        -- so a decorative Play/Endure label cannot resolve to the wrong button.
        local mainGui = pg:FindFirstChild("MainMenuGui")
        local mainFrame = mainGui and mainGui:FindFirstChild("Frame")
        local play = mainFrame and mainFrame:FindFirstChild("PlayButton")
        if play and play:IsA("GuiButton") and visible(pg, play) then
            return play, "MAIN PLAY"
        end

        local slotsGui = pg:FindFirstChild("SaveSlotsGui")
        local slotsFrame = slotsGui and slotsGui:FindFirstChild("Frame")
        local scrolling = slotsFrame and slotsFrame:FindFirstChild("ScrollingFrame")
        local slotOne = scrolling and scrolling:FindFirstChild("SaveSlot_1")
        local buttons = slotOne and slotOne:FindFirstChild("ButtonsFrame")
        local slotPlay = buttons and buttons:FindFirstChild("PlayButton")
        if slotPlay and slotPlay:IsA("GuiButton") and visible(pg, slotPlay) then
            return slotPlay, "SLOT 1 PLAY"
        end

        return nil
    end

    local function directActivate(button, stage)
        if tick() - lastActivation < 2 then return true end
        lastActivation = tick()

        local tried = attempts[button]
        if not tried then
            tried = {}
            attempts[button] = tried
        end

        if type(getconnections) == "function" and type(firesignal) == "function" then
            local selected, counts = nil, {}
            for _, name in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down"}) do
                local ok, connections = pcall(getconnections, button[name])
                local count = ok and type(connections) == "table" and #connections or 0
                counts[#counts + 1] = name .. "=" .. tostring(count)
                if count > 0 and not tried[name] and not selected then selected = name end
            end
            print("[EndHub Menu] " .. stage .. " events | " .. table.concat(counts, " | "))

            if selected then
                tried[selected] = true
                print("[EndHub Menu] " .. stage .. " direct event=" .. selected)
                if selected == "Activated" then
                    firesignal(button.Activated, nil, 1)
                elseif selected == "MouseButton1Down" then
                    local p, s = button.AbsolutePosition, button.AbsoluteSize
                    firesignal(button.MouseButton1Down, p.X + s.X / 2, p.Y + s.Y / 2)
                else
                    firesignal(button.MouseButton1Click)
                end
                print("[EndHub Menu] " .. button:GetFullName() .. " | direct clicked")
                return true
            end
        end

        -- Coordinate fallback is safe here because these are exact, unique buttons,
        -- unlike the server list where a mismatched coordinate previously hit Regions.
        if not tried.VirtualClick then
            tried.VirtualClick = true
            local p, s = button.AbsolutePosition, button.AbsoluteSize
            local x, y = p.X + s.X / 2, p.Y + s.Y / 2
            print("[EndHub Menu] " .. stage .. " exact mouse fallback=" .. x .. "," .. y)
            pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.08)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
            print("[EndHub Menu] " .. button:GetFullName() .. " | exact mouse clicked")
            return true
        end

        setStatus("MENU FIRST SCREEN PAUSED | ALL SAFE EVENTS TRIED")
        return true
    end

    function R.MenuStep()
        local button, stage = exactFirstScreenButton()
        if button then
            R.MenuEntered = false
            R.MenuClearSince = nil
            setStatus("MENU: ENTERING GAME | " .. stage)
            local ok, err = pcall(directActivate, button, stage)
            if not ok then
                setStatus("MENU FIRST SCREEN CLICK FAILED")
                warn("[EndHub Menu] " .. stage .. " error: " .. tostring(err))
            end
            return true
        end

        -- Leave the now-working Current Server logic untouched.
        return originalMenuStep()
    end

    R.FirstScreenPatchInstalled = true
    print("[EndHub] exact first-screen menu patch loaded | server entry unchanged")
end
