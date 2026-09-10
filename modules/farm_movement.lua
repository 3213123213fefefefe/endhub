return function(H)
    local C, cfg, state = H.Core, H.Config, H.State
    local TweenService = game:GetService("TweenService")
    local M = {Active = nil}
    H.FarmMovement = M
    -- Migrate saved TP profiles without changing an explicitly selected Fly mode.
    cfg.FarmMoveMode = cfg.FarmMoveMode == "Fly" and "Fly" or "Tween"
    cfg.FarmTweenSpeed = tonumber(cfg.FarmTweenSpeed) or 85

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

    function M.Cancel(owner)
        local active = M.Active
        if not active or (owner and active.Owner ~= owner) then return end
        M.Active = nil
        if active.Connection then active.Connection:Disconnect() end
        if active.Tween then
            active.Tween:Cancel()
            active.Tween:Destroy()
        end
        if active.Root and active.Root.Parent then
            active.Root.AssemblyLinearVelocity = Vector3.zero
            active.Root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    function M.IsActive(owner)
        return M.Active ~= nil and (not owner or M.Active.Owner == owner)
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
        local active = M.Active
        local same = active and active.Root == root and active.Owner == owner
            and active.Mode == mode and active.Speed == speed
            and (active.Destination - destination).Magnitude < 0.25
        C.Noclip(true)
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
            local goal = lookAt and (lookAt - destination).Magnitude > 0.01
                and CFrame.lookAt(destination, lookAt) or CFrame.new(destination) * root.CFrame.Rotation
            local ok, tween = pcall(function()
                return TweenService:Create(root,
                    TweenInfo.new(delta.Magnitude / speed, Enum.EasingStyle.Linear), {CFrame = goal})
            end)
            if not ok then
                state.Status = "TWEEN ERROR"
                warn("[EndHub Tween] " .. tostring(tween))
                return false
            end
            active = {Root = root, Owner = owner, Mode = mode, Speed = speed,
                Destination = destination, Tween = tween}
            M.Active = active
            active.Connection = tween.Completed:Connect(function(playback)
                if M.Active == active then
                    active.Completed = playback == Enum.PlaybackState.Completed
                    if not active.Completed then M.Cancel(owner) end
                end
            end)
            tween:Play()
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return false
    end

    C.Connect(H.S.RunService.Heartbeat, function()
        local active = M.Active
        if not active then return end
        local hum = C.Humanoid()
        if not allowed(active.Owner) or C.Root() ~= active.Root or not active.Root.Parent
            or not hum or hum.Health <= 0 then
            M.Cancel()
            return
        end
        -- Keep physics from adding a falling velocity during the CFrame tween.
        C.Noclip(true)
        active.Root.AssemblyLinearVelocity = Vector3.zero
        active.Root.AssemblyAngularVelocity = Vector3.zero
    end)
    C.Connect(H.S.Player.CharacterAdded, function() M.Cancel() end)
    local previousUnload = H.Unload
    function H:Unload()
        M.Cancel()
        return previousUnload(self)
    end
end
