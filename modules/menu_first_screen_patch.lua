return function(H)
    local R = H.ServerCycle
    if not R or R.FirstScreenPatchInstalled then return end

    local Player = H.S.Player
    local VIM = game:GetService("VirtualInputManager")
    local originalMenuStep = R.MenuStep
    local lastActivation = 0
    local attempt = 0

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

    local function normalize(text)
        text = tostring(text or "")
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        return string.lower(text)
    end

    local function buttonFromEndureText(pg, obj)
        if not obj then return nil end
        local isText = obj:IsA("TextButton") or obj:IsA("TextLabel")
        if not isText or normalize(obj.Text) ~= "endure" or not visible(pg, obj) then return nil end

        if obj:IsA("TextButton") then return obj end

        local node = obj.Parent
        while node and node ~= pg do
            if node:IsA("GuiButton") and visible(pg, node) then return node end
            node = node.Parent
        end
        return nil
    end

    local function findEndureButton()
        local pg = Player:FindFirstChild("PlayerGui")
        if not pg then return nil end

        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("TextButton") and normalize(obj.Text) == "endure" and visible(pg, obj) then
                return obj
            end
        end
        for _, obj in ipairs(pg:GetDescendants()) do
            local button = buttonFromEndureText(pg, obj)
            if button then return button end
        end
        return nil
    end

    local function directEvent(button)
        if type(getconnections) ~= "function" or type(firesignal) ~= "function" then
            return false, "direct-events-unavailable"
        end

        local p, s = button.AbsolutePosition, button.AbsoluteSize
        local x, y = p.X + s.X / 2, p.Y + s.Y / 2
        local order = {"Activated", "MouseButton1Click", "MouseButton1Down"}

        for _, name in ipairs(order) do
            local ok, connections = pcall(getconnections, button[name])
            local count = ok and type(connections) == "table" and #connections or 0
            if count > 0 then
                print("[EndHub Menu] ENDURE event=" .. name .. " | connections=" .. count)
                if name == "Activated" then
                    firesignal(button.Activated, nil, 1)
                elseif name == "MouseButton1Down" then
                    firesignal(button.MouseButton1Down, x, y)
                else
                    firesignal(button.MouseButton1Click)
                end
                return true, name
            end
        end

        return false, "no-connections-yet"
    end

    local function mouseClick(button)
        local p, s = button.AbsolutePosition, button.AbsoluteSize
        if s.X <= 0 or s.Y <= 0 then return false end
        local x, y = p.X + s.X / 2, p.Y + s.Y / 2

        pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.08)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        print("[EndHub Menu] ENDURE mouse click | " .. button:GetFullName())
        return true
    end

    local function clickButton(button)
        if tick() - lastActivation < 0.9 then return true end
        lastActivation = tick()
        attempt = attempt + 1

        -- Listener setup on this screen can be late. Prefer the button's own
        -- normal GUI signal when it is connected; fall back to a real mouse click.
        local ok, reason = pcall(function()
            local fired, which = directEvent(button)
            if fired then
                print("[EndHub Menu] ENDURE direct clicked | " .. tostring(which) .. " | attempt=" .. attempt)
                return true
            end
            print("[EndHub Menu] ENDURE direct not ready | " .. tostring(which) .. " | attempt=" .. attempt)
            return mouseClick(button)
        end)

        if not ok then
            warn("[EndHub Menu] ENDURE click error: " .. tostring(reason))
            return false
        end
        return reason ~= false
    end

    function R.MenuStep()
        local endure = findEndureButton()
        if endure then
            R.MenuEntered = false
            R.MenuClearSince = nil
            setStatus("MENU: CLICKING ENDURE | TRY " .. tostring(attempt + 1))
            local ok, result = pcall(clickButton, endure)
            if not ok or result == false then
                setStatus("MENU: ENDURE CLICK FAILED - RETRYING")
                if not ok then warn("[EndHub Menu] ENDURE error: " .. tostring(result)) end
            end
            return true
        end

        attempt = 0
        return originalMenuStep()
    end

    -- A menu/player check intentionally pauses the farm. In rare cases the
    -- cycle reaches the allowed in-game state again while H.State.Running stays
    -- false. Recover only after the cycle itself says it is safe to work again;
    -- this does not skip or alter any player/menu checks.
    local lastRecovery = 0
    local recoveryErrorShown = false
    task.spawn(function()
        while not H.State.Unloaded do
            local ok, err = pcall(function()
                local toggle = H.UI and H.UI.Toggles and H.UI.Toggles.EH_FarmSell
                local wantsFarm = toggle and toggle.Value == true
                local runtime = H.Sell and H.Sell.Runtime or {}
                local ready = type(R.CharacterReady) == "function" and R.CharacterReady()
                local recover = R.Enabled and R.Allowed and R.MenuEntered
                    and not R.Hopping and not R.Checking and not R.Failed
                    and ready and wantsFarm
                    and H.State.FarmSellPhase ~= "SELL"
                    and not H.Config.AutoSell and not runtime.SaleBusy and not runtime.OneShot
                    and not H.State.Running

                if recover and tick() - lastRecovery >= 2 then
                    lastRecovery = tick()
                    H.Config.AutoFarmSell = true
                    local started = H.Farm and H.Farm.Start and H.Farm.Start()
                    if started ~= false then
                        setStatus("LOOT RUNNING | SELF-RECOVERED")
                        print("[EndHub Cycle] farm self-recovered after pause")
                    else
                        print("[EndHub Cycle] farm self-recovery blocked; waiting for next cycle tick")
                    end
                end
            end)
            if not ok and not recoveryErrorShown then
                recoveryErrorShown = true
                warn("[EndHub Cycle] farm self-recovery error: " .. tostring(err))
            elseif ok then
                recoveryErrorShown = false
            end
            task.wait(1)
        end
    end)

    R.FirstScreenPatchInstalled = true
    print("[EndHub] first-screen patch loaded | Endure retry + farm self-recovery")
end
