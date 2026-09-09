return function(H)
    local CollectionService = game:GetService("CollectionService")

    H.NoKillbrick = H.NoKillbrick or {}
    local N = H.NoKillbrick

    H.Config.NoKillbrick = false
    H.Config.NoKillbrickKeywords = H.Config.NoKillbrickKeywords or {
        "killbrick",
        "kill brick",
        "killpart",
        "kill part",
        "deathbrick",
        "death brick",
        "lava",
        "void",
        "instakill",
        "instant kill",
    }

    local changed = setmetatable({}, {__mode = "k"})
    local matchedCount = 0

    local function textMatches(text)
        text = string.lower(tostring(text or ""))
        for _, keyword in ipairs(H.Config.NoKillbrickKeywords or {}) do
            keyword = string.lower(tostring(keyword or ""))
            if keyword ~= "" and string.find(text, keyword, 1, true) then
                return true
            end
        end
        return false
    end

    local function isHazard(part)
        if not part or not part:IsA("BasePart") then return false end
        if textMatches(part.Name) then return true end

        local ok, tags = pcall(CollectionService.GetTags, CollectionService, part)
        if ok then
            for _, tag in ipairs(tags) do
                if textMatches(tag) then return true end
            end
        end

        local parent = part.Parent
        for _ = 1, 3 do
            if not parent or parent == workspace then break end
            if textMatches(parent.Name) then return true end
            parent = parent.Parent
        end

        return false
    end

    local function disablePart(part)
        if not H.Config.NoKillbrick or not isHazard(part) then return false end
        if changed[part] == nil then
            changed[part] = {
                CanTouch = part.CanTouch,
            }
            matchedCount = matchedCount + 1
        end
        pcall(function() part.CanTouch = false end)
        return true
    end

    local function restoreAll()
        for part, old in pairs(changed) do
            if part and part.Parent then
                pcall(function()
                    part.CanTouch = old.CanTouch
                end)
            end
            changed[part] = nil
        end
        matchedCount = 0
    end

    function N.Scan(logMatches)
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and isHazard(obj) then
                count = count + 1
                if H.Config.NoKillbrick then disablePart(obj) end
                if logMatches then
                    print("[EndHub NoKillbrick] match | " .. obj:GetFullName())
                end
            end
        end
        matchedCount = H.Config.NoKillbrick and count or matchedCount
        H.State.NoKillbrickMatches = count
        if logMatches then
            print("[EndHub NoKillbrick] scan complete | matches=" .. tostring(count))
        end
        return count
    end

    function N.SetEnabled(value)
        H.Config.NoKillbrick = value == true
        if H.Config.NoKillbrick then
            N.Scan(false)
        else
            restoreAll()
        end
    end

    function N.Reset()
        H.Config.NoKillbrick = false
        restoreAll()
    end

    H.State.NoKillbrickMatches = H.State.NoKillbrickMatches or 0

    H.Core.Connect(workspace.DescendantAdded, function(obj)
        if H.State.Unloaded or not H.Config.NoKillbrick then return end
        if obj:IsA("BasePart") then
            task.defer(function()
                if not H.State.Unloaded and H.Config.NoKillbrick and obj.Parent then
                    disablePart(obj)
                end
            end)
        end
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            if H.Config.NoKillbrick then
                pcall(N.Scan, false)
            end
            task.wait(2)
        end
    end)

    if H.UI and H.UI.Tabs and H.UI.Tabs.Movement then
        local group = H.UI.Tabs.Movement:AddRightGroupbox("Hazard Protection")
        group:AddToggle("EH_NoKillbrick", {
            Text = "No Killbrick (local touch)",
            Default = false,
            Callback = function(value)
                N.SetEnabled(value)
            end,
        })
        group:AddButton({
            Text = "Scan / log matched hazards",
            Func = function()
                N.Scan(true)
            end,
        })
        group:AddLabel("Disables CanTouch locally only on parts whose names/tags look like KillBrick/Lava/Void/Death hazards. It does not bypass server-authoritative damage.", true)
    end

    print("[EndHub] local No Killbrick loaded")
end

