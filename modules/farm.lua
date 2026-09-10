return function(H)
    H.Farm = {}
    local F = H.Farm
    local C = H.Core

    H.Config.FarmMoveMode = H.Config.FarmMoveMode == "Fly" and "Fly" or "Tween"
    H.Config.FarmFlySpeed = tonumber(H.Config.FarmFlySpeed) or 85
    if H.Config.LootFilterEnabled == nil then H.Config.LootFilterEnabled = false end
    H.Config.LootWhitelist = type(H.Config.LootWhitelist) == "table" and H.Config.LootWhitelist or {}
    if H.Config.BackgroundPickup == nil then H.Config.BackgroundPickup = true end

    local ignored = setmetatable({}, {__mode = "k"})
    local counted = setmetatable({}, {__mode = "k"})

    local function isIgnored(obj)
        local untilTime = ignored[obj]
        if not untilTime then return false end
        if tick() >= untilTime then
            ignored[obj] = nil
            return false
        end
        return true
    end

    function F.Ignore(obj, seconds)
        if obj then ignored[obj] = tick() + (seconds or 5) end
    end

    function F.ClearTarget()
        H.FarmMovement.Cancel("loot")
        H.State.CurrentTarget = nil
        H.State.TargetStarted = 0
        H.State.PickupStarted = nil
        H.State.TargetDistance = 0
    end

    function F.SkipTarget()
        local target = H.State.CurrentTarget
        if target then
            F.Ignore(target, 20)
            F.ClearTarget()
            H.State.Status = "TARGET SKIPPED"
        end
    end

    function F.ResetStats()
        H.State.Collected = 0
        H.State.StartedAt = tick()
    end

    function F.SessionSeconds()
        if not H.State.StartedAt or H.State.StartedAt <= 0 then return 0 end
        return math.max(0, tick() - H.State.StartedAt)
    end

    function F.LootName(obj)
        if not obj then return "Unknown" end
        local name = tostring(obj.Name or "")
        if name ~= "" then return name end
        local arg = obj:FindFirstChild("Argument")
        if arg and arg:IsA("StringValue") and tostring(arg.Value) ~= "" then
            return tostring(arg.Value)
        end
        return "Unknown"
    end

    function F.GetLootNames()
        local folder = C.DropsFolder()
        local names, seen = {}, {}
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if C.IsTrinketDrop(obj) then
                    local name = F.LootName(obj)
                    if not seen[name] then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end
            end
        end
        table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
        return names
    end

    function F.GetSelectedLoot()
        local out = {}
        for name, enabled in pairs(H.Config.LootWhitelist) do
            if enabled == true then out[name] = true end
        end
        return out
    end

    function F.SetLootSelection(selection)
        H.Config.LootWhitelist = {}
        if type(selection) == "table" then
            for name, enabled in pairs(selection) do
                if enabled == true and name ~= "No loot detected" then
                    H.Config.LootWhitelist[tostring(name)] = true
                end
            end
        end
        local target = H.State.CurrentTarget
        if target and not F.Allowed(target) then F.ClearTarget() end
    end

    function F.SelectAllVisibleLoot()
        local selected = {}
        for _, name in ipairs(F.GetLootNames()) do selected[name] = true end
        H.Config.LootWhitelist = selected
        return F.GetSelectedLoot()
    end

    function F.ClearLootSelection()
        H.Config.LootWhitelist = {}
        F.ClearTarget()
    end

    function F.Allowed(obj)
        if not C.IsTrinketDrop(obj) then return false end
        if not H.Config.LootFilterEnabled then return true end
        return H.Config.LootWhitelist[F.LootName(obj)] == true
    end

    function F.Count()
        local folder = C.DropsFolder()
        local n = 0
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if F.Allowed(obj) then n = n + 1 end
            end
        end
        H.State.Detected = n
        return n
    end

    function F.Nearest()
        local folder = C.DropsFolder()
        local root = C.Root()
        if not folder or not root then return nil end

        local best, bestDist = nil, math.huge
        for _, obj in ipairs(folder:GetChildren()) do
            if F.Allowed(obj) and not isIgnored(obj) then
                local p = C.DropPart(obj)
                if p then
                    local d = (root.Position - p.Position).Magnitude
                    if d < bestDist then
                        best, bestDist = obj, d
                    end
                end
            end
        end
        return best
    end

    -- Captured from a normal manual E interaction in this game:
    -- ReplicatedStorage.Remotes.InteractPromptEvent:FireServer("PickupDrop", dropModel)
    -- This is used only after the existing local pickup-distance check passes.
    -- If the remote is missing or errors, the old E-key path remains as fallback.
    function F.TryBackgroundPickup(target)
        if H.Config.BackgroundPickup == false then return false end
        if not F.Allowed(target) then return false end

        local drops = C.DropsFolder()
        if not drops or not target:IsDescendantOf(drops) then return false end

        local remotes = H.S.RS:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("InteractPromptEvent")
        if not remote or not remote:IsA("RemoteEvent") then return false end

        local ok = pcall(function()
            remote:FireServer("PickupDrop", target)
        end)
        return ok
    end

    function F.Start()
        if H.State.Unloaded or H.State.Ready == false then return end
        if H.Boss and H.Config.BossBotEnabled then H.Boss.Stop() end
        if H.State.StartedAt <= 0 then H.State.StartedAt = tick() end
        H.State.Running = true
        H.State.Status = "SEARCHING"
    end

    function F.Stop()
        H.FarmMovement.Cancel("route")
        H.State.Running = false
        F.ClearTarget()
        H.State.Status = "PAUSED"
        if not H.Config.MovementNoclip then C.Noclip(false) end
    end

    local function moveToward(root, destination, lookAt, dt)
        H.State.Status = string.upper(H.Config.FarmMoveMode) .. " -> "
            .. tostring(H.State.CurrentTarget and H.State.CurrentTarget.Name or "loot")
        return H.FarmMovement.MoveTo(destination, lookAt, "loot", dt)
    end

    function F.Step(dt)
        if H.State.Unloaded or H.State.Ready == false or not H.State.Running or H.Config.AutoSell then
            H.FarmMovement.Cancel("loot")
            return
        end

        local root = C.Root()
        if not root then
            H.FarmMovement.Cancel("loot")
            H.State.Status = "WAIT CHARACTER"
            return
        end

        C.Noclip(true)

        local target = H.State.CurrentTarget
        if not F.Allowed(target) then
            F.ClearTarget()
            target = F.Nearest()
            H.State.CurrentTarget = target
            H.State.TargetStarted = target and tick() or 0
        end

        if not target then
            H.State.Status = H.Config.LootFilterEnabled and "SEARCHING SELECTED LOOT" or "SEARCHING"
            H.State.TargetDistance = 0
            return
        end

        local part = C.DropPart(target)
        if not part then
            F.Ignore(target, 5)
            F.ClearTarget()
            return
        end

        local destination = part.Position + Vector3.new(0, H.Config.TargetHeight, 0)
        local distance = (root.Position - part.Position).Magnitude
        H.State.TargetDistance = distance

        if (root.Position - destination).Magnitude > H.Config.PickupDistance then
            H.State.PickupStarted = nil
            moveToward(root, destination, part.Position, dt)
            return
        end
        H.FarmMovement.Cancel("loot")
        -- Slow travel must not consume the time reserved for pickup attempts.
        H.State.PickupStarted = H.State.PickupStarted or tick()
        if tick() - H.State.PickupStarted >= H.Config.TargetTimeout then
            F.Ignore(target, 8)
            F.ClearTarget()
            H.State.Status = "TARGET TIMEOUT"
            return
        end

        if H.Config.AutoPickup and tick() - H.State.LastPickup >= H.Config.PickupInterval then
            H.State.LastPickup = tick()

            local usedRemote = F.TryBackgroundPickup(target)
            if usedRemote then
                H.State.Status = "PICKUP REMOTE " .. target.Name
            else
                local sent = C.PressKey(0x45)
                H.State.Status = sent and ("PICKUP E " .. target.Name) or "WAIT PICKUP REMOTE / WINDOW FOCUS"
            end

            local before = target
            task.delay(0.40, function()
                if H.State.Unloaded then return end
                if not before.Parent then
                    if not counted[before] then
                        counted[before] = true
                        H.State.Collected = H.State.Collected + 1
                        H.State.LootPickupSerial = (H.State.LootPickupSerial or 0) + 1
                    end
                    if H.State.CurrentTarget == before then F.ClearTarget() end
                elseif not usedRemote then
                    F.Ignore(before, 2)
                    if H.State.CurrentTarget == before then F.ClearTarget() end
                end
            end)
        end
    end

    local function bindDropFolder(folder)
        if not folder then return end
        C.Connect(folder.ChildRemoved, function(obj)
            if obj == H.State.CurrentTarget and not counted[obj] then
                counted[obj] = true
                H.State.Collected = H.State.Collected + 1
                H.State.LootPickupSerial = (H.State.LootPickupSerial or 0) + 1
                H.State.Status = "COLLECTED"
                F.ClearTarget()
            end
        end)
    end

    bindDropFolder(C.DropsFolder())

    C.Connect(H.S.Player.CharacterAdded, function()
        F.ClearTarget()
        task.wait(1)
        if H.State.Running then H.State.Status = "SEARCHING" end
    end)

    C.Connect(H.S.RunService.Heartbeat, function(dt)
        if H.State.Unloaded then return end
        F.Step(dt)
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(F.Count)
            task.wait(0.5)
        end
    end)
end

