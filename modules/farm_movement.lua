return function(H)
    local C, cfg, state = H.Core, H.Config, H.State
    local TweenService = game:GetService("TweenService")
    local M = {Active = nil}
    H.FarmMovement = M
    -- Migrate saved TP profiles without changing an explicitly selected Fly mode.
    cfg.FarmMoveMode = cfg.FarmMoveMode == "Fly" and "Fly" or "Tween"
    cfg.FarmTweenSpeed = tonumber(cfg.FarmTweenSpeed) or 85
    cfg.FarmTweenSegmentLength = tonumber(cfg.FarmTweenSegmentLength) or 20
    cfg.FarmTweenPauseSeconds = tonumber(cfg.FarmTweenPauseSeconds) or 0.2
    cfg.FarmTweenGroundPauses = cfg.FarmTweenGroundPauses ~= false

    local function boundedNumber(value, fallback, minimum, maximum)
        value = tonumber(value)
        if not value or value ~= value then value = fallback end
        return math.max(minimum, math.min(maximum, value))
    end

    local function speedFor(mode)
        local value = tonumber(mode == "Fly" and cfg.FarmFlySpeed or cfg.FarmTweenSpeed)
        if not value or value ~= value then value = 85 end
        return math.max(5, math.min(250, value))
    end

    local function allowed(owner)
        if state.Unloaded or state.Ready == false then return false end
        local cycle = H.ServerCycle
        if cycle and (cycle.Hopping or cycle.Checking or cycle.Closed) then return false end
        if owner == "respawn" then
            return cycle and cycle.Enabled and cycle.DeathReturn ~= nil
        elseif owner == "seller" then
            local runtime = H.Sell and H.Sell.Runtime or {}
            return cfg.AutoSell or runtime.OneShot or runtime.InteractOnly
        elseif owner == "seller-return" then
            return cfg.AutoFarmSell and state.FarmSellPhase == "SELL"
        end
        return state.Running and not cfg.AutoSell
            and not (cfg.AutoFarmSell and state.FarmSellPhase == "SELL")
    end

    local function clearTween(active)
        if active.Connection then active.Connection:Disconnect() end
        if active.Tween then
            active.Tween:Cancel()
            active.Tween:Destroy()
        end
        active.Connection, active.Tween = nil, nil
    end

    function M.Cancel(owner)
        local active = M.Active
        if not active or (owner and active.Owner ~= owner) then return end
        M.Active = nil
        clearTween(active)
        if active.Root and active.Root.Parent then
            active.Root.AssemblyLinearVelocity = Vector3.zero
            active.Root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    function M.IsActive(owner)
        return M.Active ~= nil and (not owner or M.Active.Owner == owner)
    end

    function M.IsGroundedPause()
        local active = M.Active
        return active ~= nil and active.Phase == "pause" and active.Grounded == true
    end

    local function valid(active)
        local hum = C.Humanoid()
        return allowed(active.Owner) and C.Root() == active.Root and active.Root.Parent
            and hum and hum.Health > 0
    end

    local function hold(active)
        local root = active.Root
        -- Ground pauses use normal floor collision and gravity to keep contact.
        root.AssemblyLinearVelocity = M.IsGroundedPause()
            and Vector3.new(0, root.AssemblyLinearVelocity.Y, 0) or Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    local function groundPosition(root)
        local ok, position = pcall(function()
            local hum, character = C.Humanoid(), H.S.Player.Character
            local height = root.Size.Y * 0.5 + hum.HipHeight
            if hum.RigType == Enum.HumanoidRigType.R6 then
                local leg = character and (character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg"))
                height = height + (leg and leg.Size.Y or 2)
            end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = character and {character} or {}
            params.RespectCanCollide = true
            params.IgnoreWater = true
            params.CollisionGroup = root.CollisionGroup
            local hit = workspace:Raycast(root.Position, Vector3.new(0, -512, 0), params)
            if not hit or hit.Normal.Y < 0.55 then return nil end
            return Vector3.new(root.Position.X, hit.Position.Y + math.max(0.5, height), root.Position.Z)
        end)
        return ok and position or nil
    end

    local function pause(active, grounded)
        active.Phase, active.Completed, active.Grounded = "pause", true, grounded
        active.PauseUntil = tick() + active.PauseSeconds
        active.PausePosition = active.Root.Position
        if not grounded then active.ResumeY = nil end
        C.Noclip(not grounded)
        hold(active)
    end

    local beginPause
    local function startTween(active, position, phase, upright)
        clearTween(active)
        active.Phase, active.Completed, active.Grounded = phase, false, false
        active.PauseUntil = nil
        local root, lookAt = active.Root, active.LookAt
        if upright then
            local direction = lookAt and (lookAt - position) or root.CFrame.LookVector
            lookAt = position + Vector3.new(direction.X, 0, direction.Z)
        end
        local goal = lookAt and (lookAt - position).Magnitude > 0.01
            and CFrame.lookAt(position, lookAt)
            or (upright and CFrame.new(position) or CFrame.new(position) * root.CFrame.Rotation)
        local ok, tween = pcall(function()
            return TweenService:Create(root,
                TweenInfo.new((position - root.Position).Magnitude / active.Speed, Enum.EasingStyle.Linear), {CFrame = goal})
        end)
        if not ok then
            M.Cancel(active.Owner)
            state.Status = "TWEEN ERROR"
            warn("[EndHub Tween] " .. tostring(tween))
            return false
        end
        active.Tween = tween
        active.Connection = tween.Completed:Connect(function(playback)
            if M.Active ~= active or active.Tween ~= tween then return end
            active.Completed = playback == Enum.PlaybackState.Completed
            if not active.Completed or not valid(active) then
                M.Cancel(active.Owner)
            elseif phase == "travel" and active.PauseSeconds > 0
                and (active.Destination - root.Position).Magnitude > 0.5 then
                beginPause(active)
            elseif phase == "landing" then
                -- Check again in case the supporting surface moved or disappeared.
                local floor = groundPosition(root)
                pause(active, floor ~= nil and (floor - root.Position).Magnitude <= 0.5)
            end
        end)
        C.Noclip(true)
        hold(active)
        tween:Play()
        return true
    end

    beginPause = function(active)
        local floor = active.GroundPauses and groundPosition(active.Root) or nil
        if floor then
            active.ResumeY = active.Root.Position.Y
            if (floor - active.Root.Position).Magnitude > 0.05 then
                startTween(active, floor, "landing", true)
                return
            end
        end
        pause(active, floor ~= nil)
    end

    function M.MoveTo(destination, lookAt, owner, dt)
        local root, hum = C.Root(), C.Humanoid()
        if not root or not root.Parent or not hum or hum.Health <= 0 or not allowed(owner) then
            M.Cancel(owner)
            return false
        end
        local delta = destination - root.Position
        if delta.Magnitude <= 0.5 then
            M.Cancel(owner)
            return true
        end
        local mode = cfg.FarmMoveMode == "Fly" and "Fly" or "Tween"
        local speed = speedFor(mode)
        local segmentLength = boundedNumber(cfg.FarmTweenSegmentLength, 20, 5, 100)
        local pauseSeconds = boundedNumber(cfg.FarmTweenPauseSeconds, 0.2, 0, 1)
        local groundPauses = cfg.FarmTweenGroundPauses ~= false
        local active = M.Active
        local same = active and active.Root == root and active.Owner == owner
            and active.Mode == mode and active.Speed == speed
            and (mode == "Fly" or (active.SegmentLength == segmentLength and active.PauseSeconds == pauseSeconds
                and active.GroundPauses == groundPauses))
            and (active.Destination - destination).Magnitude < 0.25
        C.Noclip(not M.IsGroundedPause())
        if same and active.PauseUntil then
            if tick() < active.PauseUntil then
                hold(active)
                local label = active.Grounded and "GROUND PAUSE" or "TWEEN PAUSE"
                if owner == "seller" or owner == "seller-return" then
                    state.SellStatus = label
                else
                    state.Status = label
                end
                return false
            end
            -- Restore travel height smoothly before the next leg so elevated routes
            -- still make progress. Never pull a displaced character back to old X/Z.
            local resumeY = active.ResumeY
            if resumeY and (root.Position - active.PausePosition).Magnitude <= 2
                and math.abs(resumeY - root.Position.Y) > 0.5 then
                startTween(active, Vector3.new(root.Position.X, resumeY, root.Position.Z), "resume")
                return false
            end
        end
        if mode == "Fly" then
            if not same then
                M.Cancel()
                active = {Root = root, Owner = owner, Mode = mode, Speed = speed, Destination = destination}
                M.Active = active
            end
            local now = tick()
            local elapsed = dt or (active.LastStep and now - active.LastStep) or 1 / 30
            active.LastStep = now
            local step = math.min(delta.Magnitude, speed * math.max(0, math.min(0.1, elapsed)))
            local pos = root.Position + delta.Unit * step
            root.CFrame = lookAt and (lookAt - pos).Magnitude > 0.01
                and CFrame.lookAt(pos, lookAt) or CFrame.new(pos) * root.CFrame.Rotation
        elseif not same or active.Completed then
            M.Cancel()
            -- A zero pause keeps the original continuous tween behavior.
            local distance = pauseSeconds > 0 and math.min(delta.Magnitude, segmentLength) or delta.Magnitude
            local nextPosition = root.Position + delta.Unit * distance
            active = {Root = root, Owner = owner, Mode = mode, Speed = speed,
                Destination = destination, LookAt = lookAt,
                SegmentLength = segmentLength, PauseSeconds = pauseSeconds, GroundPauses = groundPauses}
            M.Active = active
            if not startTween(active, nextPosition, "travel") then return false end
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return false
    end

    C.Connect(H.S.RunService.Heartbeat, function()
        local active = M.Active
        if not active then return end
        if not valid(active) then
            M.Cancel()
            return
        end
        C.Noclip(not M.IsGroundedPause())
        hold(active)
    end)
    C.Connect(H.S.Player.CharacterAdded, function() M.Cancel() end)
    local previousUnload = H.Unload
    function H:Unload()
        M.Cancel()
        return previousUnload(self)
    end
end
