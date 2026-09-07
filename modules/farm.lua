return function(H)
    H.Farm = {}
    local F = H.Farm
    local C = H.Core

    local ignored = {}
    local counted = {}
    local boundDropFolder = nil

    -- Keep the bot's trinket detection independent from UI rebuilds / small
    -- world-structure differences. This mirrors the old working bot, but is
    -- slightly more tolerant about the object containing the marker values.
    local function dropPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end

        local handle = obj:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then return handle end

        if obj:IsA("Model") and obj.PrimaryPart then
            return obj.PrimaryPart
        end

        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    local function isTrinket(obj)
        if not obj or not obj.Parent then return false end
        local atSpawn = obj:FindFirstChild("AtTrinketSpawn") or obj:FindFirstChild("AtTrinketSpawn", true)
        local interactable = obj:FindFirstChild("IsInteractable") or obj:FindFirstChild("IsInteractable", true)
        return atSpawn ~= nil and interactable ~= nil and dropPart(obj) ~= nil
    end

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
        if obj then ignored[obj] = tick() + (seconds or 10) end
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
        table.clear(counted)
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
                if isTrinket(obj) then n = n + 1 end
            end
        end
        H.State.Detected = n
        return n
    end

    function F.Nearest()
        local folder = C.DropsFolder()
        local root = C.Root()
        if not folder or not root then return nil end

        local nearest, nearestDistance = nil, math.huge
        for _, obj in ipairs(folder:GetChildren()) do
            if isTrinket(obj) and not isIgnored(obj) then
                local part = dropPart(obj)
                if part then
                    local distance = (root.Position - part.Position).Magnitude
                    if distance < nearestDistance then
                        nearest = obj
                        nearestDistance = distance
                    end
                end
            end
        end
        return nearest
    end

    local function chooseTarget()
        local target = F.Nearest()
        H.State.CurrentTarget = target
        H.State.TargetStarted = target and tick() or 0
        H.State.TargetDistance = 0
        H.State.Status = target and ("TARGET " .. target.Name) or "NO TRINKETS"
        return target
    end

    function F.Start()
        if H.State.Unloaded then return end

        -- A manually-started bot should not silently remain blocked by an old
        -- Auto Sell state.
        if H.Config.AutoSell and H.Sell and H.Sell.Stop then
            H.Sell.Stop()
        end

        if H.State.StartedAt <= 0 then H.State.StartedAt = tick() end
        H.State.Running = true
        H.State.Status = "STARTING"
        F.ClearTarget()
        chooseTarget()
        print("[EndHub Bot] START | drops:", F.Count())
    end

    function F.Stop()
        H.State.Running = false
        F.ClearTarget()
        H.State.Status = "PAUSED"
        if not H.Config.MovementNoclip then C.Noclip(false) end
        print("[EndHub Bot] PAUSED")
    end

    function F.Step()
        if H.State.Unloaded or not H.State.Running then return end

        if H.Config.AutoSell then
            H.State.Status = "WAITING AUTO SELL"
            return
        end

        local root = C.Root()
        local hum = C.Humanoid()
        if not root or not hum then
            H.State.Status = "WAITING CHARACTER"
            return
        end

        C.Noclip(H.Config.BotNoclip)

        local target = H.State.CurrentTarget
        if not isTrinket(target) or isIgnored(target) then
            target = chooseTarget()
        end

        if not target then
            H.State.Status = "NO TRINKETS"
            return
        end

        if H.State.TargetStarted <= 0 then H.State.TargetStarted = tick() end
        if tick() - H.State.TargetStarted > H.Config.TargetTimeout then
            print("[EndHub Bot] timeout:", target.Name)
            F.Ignore(target, 10)
            F.ClearTarget()
            H.State.Status = "TARGET TIMEOUT"
            return
        end

        local part = dropPart(target)
        if not part then
            F.Ignore(target, 5)
            F.ClearTarget()
            H.State.Status = "INVALID TARGET"
            return
        end

        local destination = part.Position + Vector3.new(0, H.Config.TargetHeight, 0)
        local distanceToDestination = (destination - root.Position).Magnitude
        H.State.TargetDistance = (part.Position - root.Position).Magnitude

        -- Same behavior as the older working script: TP beside the drop, then
        -- on the following heartbeat use the normal E interaction path.
        if distanceToDestination > H.Config.PickupDistance then
            H.State.Status = "TELEPORTING -> " .. target.Name
            root.CFrame = CFrame.new(destination, part.Position)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            return
        end

        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        if not H.Config.AutoPickup then
            H.State.Status = "IN RANGE / AUTO PICKUP OFF"
            return
        end

        -- Do not clear/ignore the target after only one E press. The old bot
        -- kept pressing E at the configured interval until the drop actually
        -- disappeared. That is much more reliable when interaction/UI takes a
        -- few frames to settle.
        if tick() - H.State.LastPickup >= H.Config.PickupInterval then
            H.State.LastPickup = tick()
            H.State.Status = "PICKING UP -> " .. target.Name
            C.PressKey(0x45)
        end
    end

    local function bindDropFolder(folder)
        if not folder or boundDropFolder == folder then return end
        boundDropFolder = folder

        C.Connect(folder.ChildRemoved, function(obj)
            if counted[obj] then return end
            if obj == H.State.CurrentTarget or isTrinket(obj) then
                counted[obj] = true
                H.State.Collected = H.State.Collected + 1
                if obj == H.State.CurrentTarget then
                    F.ClearTarget()
                    H.State.Status = "COLLECTED"
                end
            end
        end)

        C.Connect(folder.ChildAdded, function(obj)
            ignored[obj] = nil
        end)
    end

    bindDropFolder(C.DropsFolder())

    C.Connect(workspace.ChildAdded, function(child)
        if child.Name == "Drops" then
            task.defer(function() bindDropFolder(child) end)
        end
    end)

    C.Connect(H.S.Player.CharacterAdded, function()
        F.ClearTarget()
        task.wait(1)
        if H.State.Running then H.State.Status = "SEARCHING" end
    end)

    C.Connect(H.S.RunService.Heartbeat, function()
        if H.State.Unloaded then return end
        local folder = C.DropsFolder()
        if folder and folder ~= boundDropFolder then bindDropFolder(folder) end
        F.Step()
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(F.Count)
            task.wait(0.5)
        end
    end)

    -- Small diagnostic helper so the UI/keybind can verify the bot without
    -- needing a separate console script.
    function F.DebugState()
        local folder = C.DropsFolder()
        return {
            Running = H.State.Running,
            HasCharacter = C.Root() ~= nil,
            HasDropsFolder = folder ~= nil,
            DropChildren = folder and #folder:GetChildren() or 0,
            Trinkets = F.Count(),
            Target = H.State.CurrentTarget and H.State.CurrentTarget.Name or "None",
            Status = H.State.Status,
        }
    end
end
