return function(H)
    if H.PerformancePatchInstalled then return end
    H.PerformancePatchInstalled = true

    local C = H.Core
    local cfg = H.Config
    local state = H.State

    ------------------------------------------------------------------------
    -- Noclip debounce / arbitration
    ------------------------------------------------------------------------
    if C and type(C.Noclip) == "function" and not C._EndHubPerfNoclipWrapped then
        local originalNoclip = C.Noclip
        local lastApplied = nil
        local lastCharacter = nil
        local lastRefresh = 0

        local function automationNeedsNoclip()
            if cfg.MovementNoclip or cfg.MovementFly then return true end
            if state.Running then
                if cfg.BotNoclip then return true end
                if tostring(cfg.FarmMoveMode or "") == "Fly" then return true end
            end
            if cfg.BossBotEnabled and cfg.BossNoclip ~= false then return true end
            if cfg.MobFarmEnabled and cfg.MobFarmNoclip ~= false then return true end
            return false
        end

        C.Noclip = function(active)
            active = active and true or false
            if not active and automationNeedsNoclip() then active = true end

            local character = C.Character and C.Character() or nil
            local now = tick()
            if active == lastApplied and character == lastCharacter then
                if not active or (now - lastRefresh) < 1.0 then return end
            end

            lastApplied = active
            lastCharacter = character
            lastRefresh = now
            return originalNoclip(active)
        end

        C._EndHubPerfNoclipWrapped = true
        if C.Connect and H.S and H.S.Player then
            C.Connect(H.S.Player.CharacterAdded, function()
                lastApplied = nil
                lastCharacter = nil
                lastRefresh = 0
            end)
        end
    end

    ------------------------------------------------------------------------
    -- Trinket farm CPU throttle
    ------------------------------------------------------------------------
    if H.Farm and type(H.Farm.Step) == "function" and not H.Farm._EndHubPerfStepWrapped then
        local originalStep = H.Farm.Step
        local lastStep = 0
        H.Farm.Step = function(dt)
            local now = tick()
            if now - lastStep < (1 / 30) then return end
            local elapsed = lastStep > 0 and (now - lastStep) or (dt or 1 / 30)
            lastStep = now
            return originalStep(elapsed)
        end
        H.Farm._EndHubPerfStepWrapped = true
    end

    ------------------------------------------------------------------------
    -- Background pickup de-duplication
    ------------------------------------------------------------------------
    if H.Farm and type(H.Farm.TryBackgroundPickup) == "function"
        and not H.Farm._EndHubPerfPickupWrapped then
        local originalPickup = H.Farm.TryBackgroundPickup
        local lastTarget = nil
        local lastFire = 0

        H.Farm.TryBackgroundPickup = function(target)
            local now = tick()
            if target == lastTarget and (now - lastFire) < 0.45 then
                return true
            end

            local ok = originalPickup(target)
            if ok then
                lastTarget = target
                lastFire = now
            end
            return ok
        end
        H.Farm._EndHubPerfPickupWrapped = true
    end

    ------------------------------------------------------------------------
    -- Confirm pickup before advancing
    --
    -- farm.lua used to schedule a 0.40s check and clear the target even when
    -- the server had not removed the drop yet. With latency, that makes the bot
    -- leave an item and move to the next one. Keep the current target locked
    -- until it actually leaves Workspace.Drops. A hard timeout still prevents
    -- one broken/unpickable drop from freezing the route forever.
    ------------------------------------------------------------------------
    if H.Farm and type(H.Farm.ClearTarget) == "function"
        and type(H.Farm.TryBackgroundPickup) == "function"
        and not H.Farm._EndHubPickupConfirmWrapped then

        local F = H.Farm
        local originalClearTarget = F.ClearTarget
        local pickupWithDedup = F.TryBackgroundPickup
        local originalSkip = F.SkipTarget
        local pendingTarget = nil
        local pendingSince = 0
        local forceClear = false
        local settleUntil = 0

        local function stillInDrops(target)
            local drops = C.DropsFolder and C.DropsFolder() or nil
            return target and target.Parent and drops and target:IsDescendantOf(drops)
        end

        F.TryBackgroundPickup = function(target)
            local ok = pickupWithDedup(target)
            if ok and target then
                if pendingTarget ~= target then
                    pendingTarget = target
                    pendingSince = tick()
                end
            end
            return ok
        end

        F.ClearTarget = function()
            if not forceClear and pendingTarget and state.CurrentTarget == pendingTarget then
                if stillInDrops(pendingTarget) then
                    state.Status = "WAIT PICKUP CONFIRM " .. tostring(pendingTarget.Name)
                    return false
                end
                -- Server removed/reparented the drop: pickup is confirmed.
                pendingTarget = nil
                pendingSince = 0
                settleUntil = tick() + 0.12
            end
            return originalClearTarget()
        end

        if type(originalSkip) == "function" then
            F.SkipTarget = function(...)
                forceClear = true
                pendingTarget, pendingSince = nil, 0
                local result = originalSkip(...)
                forceClear = false
                return result
            end
        end

        local throttledStep = F.Step
        F.Step = function(dt)
            local now = tick()
            if now < settleUntil then
                state.Status = "PICKUP CONFIRMED"
                return
            end

            if pendingTarget then
                if not stillInDrops(pendingTarget) then
                    pendingTarget, pendingSince = nil, 0
                    settleUntil = now + 0.12
                    forceClear = true
                    originalClearTarget()
                    forceClear = false
                    state.Status = "PICKUP CONFIRMED"
                    return
                end

                local timeout = math.max(3, tonumber(cfg.TargetTimeout) or 15)
                if pendingSince > 0 and now - pendingSince >= timeout then
                    local stuck = pendingTarget
                    pendingTarget, pendingSince = nil, 0
                    forceClear = true
                    if F.Ignore then F.Ignore(stuck, 8) end
                    originalClearTarget()
                    forceClear = false
                    state.Status = "PICKUP CONFIRM TIMEOUT"
                    return
                end

                -- Stay on exactly this drop. The wrapped normal Step may retry
                -- PickupDrop at the configured interval, but cannot pick a new
                -- target until the current one is confirmed removed.
                if state.CurrentTarget ~= pendingTarget then
                    state.CurrentTarget = pendingTarget
                end
            end

            return throttledStep(dt)
        end

        F._EndHubPickupConfirmWrapped = true
    end

    ------------------------------------------------------------------------
    -- Capacity GUI scan cache
    ------------------------------------------------------------------------
    if C and type(C.ReadCapacity) == "function" and not C._EndHubPerfCapacityWrapped then
        local originalReadCapacity = C.ReadCapacity
        local cachedA, cachedB, cachedAt = nil, nil, 0

        C.ReadCapacity = function()
            local now = tick()
            if cachedA and cachedB and now - cachedAt < 0.20 then
                return cachedA, cachedB
            end

            local a, b = originalReadCapacity()
            if a and b then cachedA, cachedB, cachedAt = a, b, now end
            return a, b
        end
        C._EndHubPerfCapacityWrapped = true
    end

    print("[EndHub] FPS patch loaded | noclip debounced | farm 30Hz | pickup de-dupe + confirm | capacity cache")
end
