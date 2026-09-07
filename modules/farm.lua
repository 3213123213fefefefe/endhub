return function(H)
    H.Farm = {}
    local F = H.Farm
    local C = H.Core

    local ignored = {}
    local counted = {}

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
        H.State.CurrentTarget = nil
        H.State.TargetStarted = 0
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

    function F.Count()
        local folder = C.DropsFolder()
        local n = 0
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if C.IsTrinketDrop(obj) then n = n + 1 end
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
            if C.IsTrinketDrop(obj) and not isIgnored(obj) then
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

    function F.Start()
        if H.State.Unloaded then return end
        if H.State.StartedAt <= 0 then H.State.StartedAt = tick() end
        H.State.Running = true
        H.State.Status = "SEARCHING"
    end

    function F.Stop()
        H.State.Running = false
        F.ClearTarget()
        H.State.Status = "PAUSED"
        if not H.Config.MovementNoclip then C.Noclip(false) end
    end

    function F.Step()
        if H.State.Unloaded or not H.State.Running then return end
        if H.Config.AutoSell then return end

        local root = C.Root()
        if not root then
            H.State.Status = "WAIT CHARACTER"
            return
        end

        C.Noclip(H.Config.BotNoclip)

        local target = H.State.CurrentTarget
        if not C.IsTrinketDrop(target) then
            target = F.Nearest()
            H.State.CurrentTarget = target
            H.State.TargetStarted = target and tick() or 0
        end

        if not target then
            H.State.Status = "SEARCHING"
            H.State.TargetDistance = 0
            return
        end

        if H.State.TargetStarted > 0 and tick() - H.State.TargetStarted >= H.Config.TargetTimeout then
            F.Ignore(target, 8)
            F.ClearTarget()
            H.State.Status = "TARGET TIMEOUT"
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
            H.State.Status = "TP -> " .. target.Name
            C.Teleport(destination, part.Position)
            return
        end

        if H.Config.AutoPickup and tick() - H.State.LastPickup >= H.Config.PickupInterval then
            H.State.LastPickup = tick()
            H.State.Status = "PICKUP " .. target.Name
            C.PressKey(0x45)

            local before = target
            task.delay(0.40, function()
                if H.State.Unloaded then return end
                if not before.Parent then
                    if not counted[before] then
                        counted[before] = true
                        H.State.Collected = H.State.Collected + 1
                    end
                else
                    F.Ignore(before, 2)
                end
                if H.State.CurrentTarget == before then F.ClearTarget() end
            end)
        end
    end

    local function bindDropFolder(folder)
        if not folder then return end
        C.Connect(folder.ChildRemoved, function(obj)
            if obj == H.State.CurrentTarget and not counted[obj] then
                counted[obj] = true
                H.State.Collected = H.State.Collected + 1
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

    C.Connect(H.S.RunService.Heartbeat, function()
        if H.State.Unloaded then return end
        F.Step()
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(F.Count)
            task.wait(0.5)
        end
    end)
end
