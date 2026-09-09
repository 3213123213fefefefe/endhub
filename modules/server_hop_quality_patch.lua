return function(H)
    local R = H.ServerCycle
    if not R or R.QualityHopPatchInstalled then return end

    local C = H.Core
    local cfg = H.Config
    local Player = H.S.Player
    local Http = H.S.HttpService
    local Teleports = game:GetService("TeleportService")
    local PLACE = game.PlaceId
    local JOB = tostring(game.JobId)
    local visitedFile = "EndHub/serverhop_visited.json"

    cfg.ServerHopVisitedResetSeconds = math.clamp(tonumber(cfg.ServerHopVisitedResetSeconds) or 480, 300, 600)
    cfg.ServerHopPingTarget = math.max(20, tonumber(cfg.ServerHopPingTarget) or 120)
    cfg.ServerHopPages = math.clamp(math.floor(tonumber(cfg.ServerHopPages) or 3), 1, 6)

    local function status(value)
        if R.Status ~= value then print("[EndHub Cycle] " .. value) end
        R.Status = value
        H.State.ServerCycleStatus = value
    end

    local function alive(generation)
        return not R.Closed and not H.State.Unloaded and R.Enabled
            and (not generation or generation == R.Generation)
    end

    local function readVisits()
        local visits = C.ReadJson(visitedFile)
        return type(visits) == "table" and visits or {}
    end

    local function saveVisits(visits)
        C.WriteJson(visitedFile, visits)
    end

    local function visitKey(id)
        return tostring(PLACE) .. ":" .. tostring(id)
    end

    local function pruneVisits(visits)
        local now = os.time()
        local ttl = cfg.ServerHopVisitedResetSeconds
        local changed = false
        for key, t in pairs(visits) do
            if type(t) ~= "number" or now - t >= ttl then
                visits[key] = nil
                changed = true
            end
        end
        if changed then saveVisits(visits) end
        return visits
    end

    local function markVisited(visits, id)
        visits[visitKey(id)] = os.time()
        saveVisits(visits)
    end

    local function getPage(cursor, generation)
        if not alive(generation) then return nil, "cancelled" end
        local url = "https://games.roblox.com/v1/games/" .. tostring(PLACE)
            .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor then url = url .. "&cursor=" .. Http:UrlEncode(cursor) end

        local done, ok, decoded = false, false, nil
        task.spawn(function()
            ok, decoded = pcall(function()
                return Http:JSONDecode(game:HttpGet(url))
            end)
            done = true
        end)

        local deadline = tick() + 12
        while not done and alive(generation) and tick() < deadline do task.wait(0.10) end
        if not alive(generation) then return nil, "cancelled" end
        if not done then return nil, "SERVER LIST TIMEOUT" end
        if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
            return nil, "SERVER LIST UNAVAILABLE"
        end
        return decoded
    end

    local function quality(server)
        local ping = tonumber(server.ping)
        local fps = tonumber(server.fps)
        local playing = tonumber(server.playing) or math.huge
        local maxPlayers = tonumber(server.maxPlayers) or 0
        local occupancy = maxPlayers > 0 and (playing / maxPlayers) or 1

        -- API ping is the strongest signal when present. FPS and occupancy are
        -- secondary tie breakers so a healthy, less-loaded server wins.
        return ping or math.huge, -(fps or 0), occupancy, playing
    end

    local function better(a, b)
        local ap, af, ao, ac = quality(a)
        local bp, bf, bo, bc = quality(b)
        if ap ~= bp then return ap < bp end
        if af ~= bf then return af < bf end
        if ao ~= bo then return ao < bo end
        return ac < bc
    end

    local function chooseServer(generation)
        local visits = pruneVisits(readVisits())
        local fresh, repeated = {}, {}
        local cursor = nil

        for _ = 1, cfg.ServerHopPages do
            local page, err = getPage(cursor, generation)
            if not page then return nil, err end

            for _, server in ipairs(page.data) do
                if type(server.id) == "string" and server.id ~= JOB
                    and type(server.playing) == "number" and type(server.maxPlayers) == "number"
                    and server.playing < server.maxPlayers then
                    local row = {
                        id = server.id,
                        ping = tonumber(server.ping),
                        fps = tonumber(server.fps),
                        playing = server.playing,
                        maxPlayers = server.maxPlayers,
                        lastVisit = visits[visitKey(server.id)],
                    }
                    if row.lastVisit then repeated[#repeated + 1] = row
                    else fresh[#fresh + 1] = row end
                end
            end

            cursor = page.nextPageCursor
            if type(cursor) ~= "string" or cursor == "" then break end
        end

        table.sort(fresh, better)
        if #fresh > 0 then return fresh[1], visits, false end

        -- Avoid repeats whenever possible. If every available server is still in
        -- the 5-10 minute history, use the least-recently visited one instead of
        -- deadlocking the cycle.
        table.sort(repeated, function(a, b)
            if a.lastVisit ~= b.lastVisit then return (a.lastVisit or 0) < (b.lastVisit or 0) end
            return better(a, b)
        end)
        if #repeated > 0 then return repeated[1], visits, true end
        return nil, visits, false, "NO SERVER WITH SPACE"
    end

    local oldRequestHop = R.RequestHop
    R.RequestHop = function(reason)
        if not alive() or R.Hopping then return false end
        R.Hopping = true
        R.HopOwned = true

        -- Match the original cycle's pause behavior without exposing its locals.
        R.Allowed = false
        cfg.AutoFarmSell = false
        if H.Sell then H.Sell.Stop() end
        if H.Farm then H.Farm.Stop() end

        local generation = R.Generation
        status("HOP REQUESTED: " .. tostring(reason or "manual") .. " | FINDING LOW PING")
        if H.PersistenceManager and H.PersistenceManager.SaveConfig then
            pcall(H.PersistenceManager.SaveConfig, true)
        end
        if R.QueueBootstrap then R.QueueBootstrap() end

        local visits = pruneVisits(readVisits())
        markVisited(visits, JOB)

        task.spawn(function()
            local lastError = "TELEPORT NOT COMPLETED"
            for attempt = 1, 3 do
                if not alive(generation) then return end

                local selected, currentVisits, repeated, err = chooseServer(generation)
                if not alive(generation) then return end
                if selected then
                    R.HopFailed, R.HopError = false, nil
                    R.TargetServer = selected.id
                    markVisited(currentVisits, selected.id)

                    local pingText = selected.ping and (tostring(math.floor(selected.ping + 0.5)) .. "ms") or "ping?"
                    local fpsText = selected.fps and (tostring(math.floor(selected.fps + 0.5)) .. "fps") or "fps?"
                    status(string.format("TELEPORTING LOW PING %s | %s | %s | %d/%d%s",
                        selected.id, pingText, fpsText, selected.playing, selected.maxPlayers,
                        repeated and " | REPEAT FALLBACK" or ""))

                    local ok, errorMessage = pcall(function()
                        Teleports:TeleportToPlaceInstance(PLACE, selected.id, Player)
                    end)
                    if not ok then
                        R.HopFailed = true
                        lastError = tostring(errorMessage)
                    end

                    local deadline = tick() + 30
                    while alive(generation) and not R.HopFailed and tick() < deadline do task.wait(0.25) end
                    lastError = R.HopError or lastError
                else
                    lastError = err or "NO SERVER WITH SPACE"
                end

                if alive(generation) and attempt < 3 then
                    status("HOP RETRY: " .. tostring(lastError))
                    task.wait(attempt * 3)
                end
            end

            if alive(generation) then
                R.Hopping = false
                R.HopOwned = false
                R.Failed = true
                status("HOP PAUSED: " .. tostring(lastError) .. " | USE RETRY")
            end
        end)
        return true
    end

    H.ServerHop = H.ServerHop or {}
    H.ServerHop.Request = R.RequestHop
    R.QualityHopPatchInstalled = true
    R.OriginalRequestHop = oldRequestHop
    print(string.format("[EndHub] quality server hop loaded | visited TTL=%ds | pages=%d | prefers lowest API ping",
        cfg.ServerHopVisitedResetSeconds, cfg.ServerHopPages))
end
