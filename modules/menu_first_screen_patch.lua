return function(H)
    local R = H.ServerCycle
    if not R or R.FirstScreenPatchInstalled then return end

    local Player = H.S.Player
    local VIM = game:GetService("VirtualInputManager")
    local originalMenuStep = R.MenuStep
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

        -- First try direct button text, then a TextLabel nested inside the real button.
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

    local function clickButton(button)
        if tick() - lastActivation < 1.25 then return true end
        lastActivation = tick()

        local p, s = button.AbsolutePosition, button.AbsoluteSize
        if s.X <= 0 or s.Y <= 0 then return false end
        local x, y = p.X + s.X / 2, p.Y + s.Y / 2

        pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.06)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        print("[EndHub Menu] ENDURE | clicked | " .. button:GetFullName())
        return true
    end

    function R.MenuStep()
        local endure = findEndureButton()
        if endure then
            R.MenuEntered = false
            R.MenuClearSince = nil
            setStatus("MENU: CLICKING ENDURE")
            local ok, result = pcall(clickButton, endure)
            if not ok or result == false then
                setStatus("MENU: ENDURE CLICK FAILED")
                if not ok then warn("[EndHub Menu] ENDURE error: " .. tostring(result)) end
            end
            return true
        end

        -- First-screen patch does one thing only: click Endure.
        -- Once Endure is gone, keep the already-working server-menu flow untouched.
        return originalMenuStep()
    end

    R.FirstScreenPatchInstalled = true
    print("[EndHub] first-screen patch loaded | Endure only | server entry unchanged")
end
