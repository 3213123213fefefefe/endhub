return function(H)
    if H.NoclipStrengthPatchInstalled then return end
    H.NoclipStrengthPatchInstalled = true

    local C = H.Core
    local cfg = H.Config
    local state = H.State
    local runService = H.S and H.S.RunService
    if not C or type(C.Noclip) ~= "function" or not runService then return end

    local originalNoclip = C.Noclip
    local enabled = false
    local parts = {}
    local trackedCharacter = nil
    local steppedConn = nil
    local addedConn = nil
    local removingConn = nil

    local function automationNeedsNoclip()
        if H.FarmMovement and H.FarmMovement.IsActive() then return true end
        if cfg.MovementNoclip or cfg.MovementFly then return true end
        if state.Running then
            if cfg.BotNoclip then return true end
            if tostring(cfg.FarmMoveMode or "") == "Fly" then return true end
        end
        if cfg.BossBotEnabled and cfg.BossNoclip ~= false then return true end
        if cfg.MobFarmEnabled and cfg.MobFarmNoclip ~= false then return true end
        return false
    end

    local function rememberPart(obj)
        if not obj or not obj:IsA("BasePart") then return end
        if H.OriginalCollision[obj] == nil then
            H.OriginalCollision[obj] = obj.CanCollide
        end
        parts[obj] = true
        obj.CanCollide = false
    end

    local function rebuild(character)
        table.clear(parts)
        trackedCharacter = character
        if not character then return end
        for _, obj in ipairs(character:GetDescendants()) do
            rememberPart(obj)
        end
    end

    local function disconnectCharacterSignals()
        if addedConn then addedConn:Disconnect() addedConn = nil end
        if removingConn then removingConn:Disconnect() removingConn = nil end
    end

    local function attachCharacter(character)
        disconnectCharacterSignals()
        rebuild(character)
        if not character then return end
        addedConn = character.DescendantAdded:Connect(function(obj)
            if enabled then rememberPart(obj) end
        end)
        removingConn = character.DescendantRemoving:Connect(function(obj)
            parts[obj] = nil
        end)
    end

    local function ensureStepped()
        if steppedConn then return end
        steppedConn = runService.Stepped:Connect(function()
            if not enabled or H.State.Unloaded then return end
            local character = C.Character and C.Character() or nil
            if character ~= trackedCharacter then
                attachCharacter(character)
            end
            for part in pairs(parts) do
                if part and part.Parent then
                    if part.CanCollide then part.CanCollide = false end
                else
                    parts[part] = nil
                end
            end
        end)
        H.Connections[#H.Connections + 1] = steppedConn
    end

    C.Noclip = function(active)
        active = active and true or false
        if H.FarmMovement and H.FarmMovement.IsGroundedPause() then
            active = false
        elseif not active and automationNeedsNoclip() then active = true end

        if active then
            enabled = true
            ensureStepped()
            local character = C.Character and C.Character() or nil
            if character ~= trackedCharacter then attachCharacter(character) end
            for part in pairs(parts) do
                if part and part.Parent and part.CanCollide then part.CanCollide = false end
            end
            return originalNoclip(true)
        end

        if enabled then
            enabled = false
            disconnectCharacterSignals()
            table.clear(parts)
            trackedCharacter = nil
        end
        return originalNoclip(false)
    end

    if C.Connect and H.S and H.S.Player then
        C.Connect(H.S.Player.CharacterAdded, function(character)
            if enabled then attachCharacter(character) end
        end)
    end

    print("[EndHub] stronger noclip loaded | cached character parts + per-step collision enforcement")
end
