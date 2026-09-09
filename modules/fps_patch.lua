return function(H)
    if H.PerformancePatchInstalled then return end
    H.PerformancePatchInstalled = true

    local C = H.Core
    local cfg = H.Config
    local state = H.State

    ------------------------------------------------------------------------
    -- Noclip debounce / arbitration
    --
    -- Several modules call C.Noclip every Heartbeat/RenderStepped. Worse,
    -- Movement used to request OFF while Farm Fly requested ON, causing a full
    -- character GetDescendants scan + restore repeatedly every frame.
    -- Keep the final requested state stable and refresh at most once/second.
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

            -- A module asking for OFF must not fight another active automation
            -- that currently requires noclip.
            if not active and automationNeedsNoclip() then
                active = true
            end

            local character = C.Character and C.Character() or nil
            local now = tick()

            if active == lastApplied and character == lastCharacter then
                -- When active, rescan only occasionally so newly-added character
                -- parts/accessories are still covered without doing it every frame.
                if not active or (now - lastRefresh) < 1.0 then
                    return
                end
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
    -- The farm was being evaluated every Heartbeat even though Fly itself is
    -- already limited to ~30 Hz. Limit the whole final Step to ~30 Hz.
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
    -- Prevent the same drop remote from being fired several times while the
    -- 0.40s pickup confirmation is still pending.
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
    -- Capacity GUI scan cache
    -- ReadCapacity walks PlayerGui descendants. Multiple status/sell loops can
    -- ask for it in the same frame, so cache successful reads for 0.20s.
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
            if a and b then
                cachedA, cachedB, cachedAt = a, b, now
            end
            return a, b
        end
        C._EndHubPerfCapacityWrapped = true
    end

    print("[EndHub] FPS patch loaded | noclip debounced | farm 30Hz | pickup de-dupe | capacity cache")
end
