return function(H)
    local C = H.Core
    local ENV = getgenv()
    local HttpService = H.S.HttpService

    H.Persistence = H.Persistence or {}
    H.Persistence.ConfigFile = H.Persistence.ConfigFile or "EndHub/config.json"
    H.Persistence.PositionsFile = H.Persistence.PositionsFile or "EndHub/bot_positions.json"

    H.PersistenceManager = {}
    local P = H.PersistenceManager

    -- Runtime/action toggles are intentionally not restored as ON. The user's
    -- actual settings are preserved, but loading EndHub never immediately
    -- starts selling/flying/speed modifying/boss/mob farming/etc. by itself.
    local transient = {
        AutoSell = true,
        AutoFarmSell = true,
        MovementFly = true,
        MovementNoclip = true,
        Desync = true,
        SpeedModifierEnabled = true,
        BossBotEnabled = true,
        MobFarmEnabled = true,
        NoKillbrick = true,
    }

    local function serializableCopy(value, depth)
        depth = depth or 0
        if depth > 12 then return nil end

        local t = type(value)
        if t == "boolean" or t == "number" or t == "string" then
            return value
        end
        if t ~= "table" then return nil end

        local out = {}
        for k, v in pairs(value) do
            if type(k) == "string" or type(k) == "number" then
                local copied = serializableCopy(v, depth + 1)
                if copied ~= nil then out[k] = copied end
            end
        end
        return out
    end

    local function mergeInto(dst, src, depth)
        depth = depth or 0
        if depth > 12 or type(dst) ~= "table" or type(src) ~= "table" then return end

        for k, v in pairs(src) do
            if not transient[k] then
                if type(v) == "table" then
                    if type(dst[k]) ~= "table" then dst[k] = {} end
                    mergeInto(dst[k], v, depth + 1)
                elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
                    dst[k] = v
                end
            end
        end
    end

    function P.ConfigSnapshot()
        local out = serializableCopy(H.Config) or {}
        for key in pairs(transient) do out[key] = nil end
        return out
    end

    function P.LoadConfig()
        local saved = C.ReadProfile(H.Persistence.ConfigFile, "config.json")
        if type(saved) == "table" then
            mergeInto(H.Config, saved)
            H.State.PersistenceStatus = "CONFIG LOADED"
            return true
        end
        H.State.PersistenceStatus = "NO CONFIG YET"
        return false
    end

    local lastConfigJson = nil
    function P.SaveConfig(force)
        local snapshot = P.ConfigSnapshot()
        local okEncode, raw = pcall(HttpService.JSONEncode, HttpService, snapshot)
        if not okEncode then
            H.State.PersistenceStatus = "CONFIG ENCODE FAILED"
            return false
        end
        if not force and raw == lastConfigJson then return true end

        local ok = C.WriteJson(H.Persistence.ConfigFile, snapshot)
        if ok then
            lastConfigJson = raw
            H.State.PersistenceStatus = "CONFIG SAVED"
            return true
        end

        H.State.PersistenceStatus = "FILE I/O NOT AVAILABLE"
        return false
    end

    ENV.ENDHUB_BOT_POSITIONS = ENV.ENDHUB_BOT_POSITIONS or {}
    local diskPositions = C.ReadProfile(H.Persistence.PositionsFile, "bot_positions.json")
    if type(diskPositions) == "table" then
        for name, coords in pairs(diskPositions) do
            if ENV.ENDHUB_BOT_POSITIONS[name] == nil then
                ENV.ENDHUB_BOT_POSITIONS[name] = coords
            end
        end
    end

    local function coordsToVector(coords)
        if type(coords) ~= "table" then return nil end
        local x = tonumber(coords[1] or coords.X or coords.x)
        local y = tonumber(coords[2] or coords.Y or coords.y)
        local z = tonumber(coords[3] or coords.Z or coords.z)
        if x and y and z then return Vector3.new(x, y, z) end
        return nil
    end

    function P.SavePosition(name, pos)
        if type(name) ~= "string" or name == "" or typeof(pos) ~= "Vector3" then return false end
        ENV.ENDHUB_BOT_POSITIONS[name] = {pos.X, pos.Y, pos.Z}
        local ok = C.WriteJson(H.Persistence.PositionsFile, ENV.ENDHUB_BOT_POSITIONS)
        H.State.PersistenceStatus = ok and ("POSITION SAVED: " .. name) or "POSITION SAVE FAILED"
        return ok
    end

    function P.GetPosition(name)
        return coordsToVector(ENV.ENDHUB_BOT_POSITIONS[name])
    end

    function P.ClearPosition(name)
        ENV.ENDHUB_BOT_POSITIONS[name] = nil
        C.WriteJson(H.Persistence.PositionsFile, ENV.ENDHUB_BOT_POSITIONS)
    end

    function P.SaveCurrentPosition(name)
        local root = C.Root()
        return root and P.SavePosition(name, root.Position) or false
    end

    function P.SaveAll(force)
        local okConfig = P.SaveConfig(force == true)
        local seller = C.GetSavedSeller()
        if seller then
            P.SavePosition("Clement, Merchant", seller)
        end
        if H.Core and H.Core.SaveKeybinds then pcall(H.Core.SaveKeybinds) end
        return okConfig
    end

    P.LoadConfig()

    local savedSeller = C.GetSavedSeller()
    if savedSeller then
        ENV.ENDHUB_BOT_POSITIONS["Clement, Merchant"] = {savedSeller.X, savedSeller.Y, savedSeller.Z}
    else
        local legacyPos = P.GetPosition("Clement, Merchant")
        if legacyPos then C.SaveSellerPosition(legacyPos) end
    end

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                P.SaveConfig(false)

                local seller = C.GetSavedSeller()
                if seller then
                    local old = P.GetPosition("Clement, Merchant")
                    if not old or (old - seller).Magnitude > 0.05 then
                        P.SavePosition("Clement, Merchant", seller)
                    end
                end
            end)
            task.wait(5)
        end
    end)

    print("[EndHub] persistence loaded | config + keybinds + bot positions")
end

