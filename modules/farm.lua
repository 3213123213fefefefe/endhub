return function(H)
    H.Farm = {}
    local F = H.Farm
    local C = H.Core

    local ignored = {}

    local function isIgnored(obj)
        local untilTime = ignored[obj]
        if not untilTime then return false end
        if tick() >= untilTime then
            ignored[obj] = nil
            return false
        end
        return true
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
                        best = obj
                        bestDist = d
                    end
                end
            end
        end
        return best
    end

    function F.Start()
        if H.State.Unloaded then return end
        H.State.Running = true
        H.State.Status = "SEARCHING"
    end

    function F.Stop()
        H.State.Running = false
        H.State.CurrentTarget = nil
        H.State.Status = "PAUSED"
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
        end

        if not target then
            H.State.Status = "SEARCHING"
            return
        end

        local part = C.DropPart(target)
        if not part then
            ignored[target] = tick() + 5
            H.State.CurrentTarget = nil
            return
        end

        local destination = part.Position + Vector3.new(0, H.Config.TargetHeight, 0)
        local distance = (root.Position - destination).Magnitude

        if distance > H.Config.PickupDistance then
            H.State.Status = "TP -> " .. target.Name
            C.Teleport(destination, part.Position)
            return
        end

        if H.Config.AutoPickup and tick() - H.State.LastPickup >= H.Config.PickupInterval then
            H.State.LastPickup = tick()
            H.State.Status = "PICKUP " .. target.Name
            C.PressKey(0x45)

            local before = target
            task.delay(0.35, function()
                if H.State.Unloaded then return end
                if not before.Parent then
                    H.State.Collected = H.State.Collected + 1
                else
                    ignored[before] = tick() + 2
                end
                if H.State.CurrentTarget == before then
                    H.State.CurrentTarget = nil
                end
            end)
        end
    end

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
