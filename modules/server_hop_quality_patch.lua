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
    local visitedFile = H.Persistence and H.Persistence.VisitedFile or "EndHub/serverhop_visited.json"

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
        if not id then return end
        visits[visitKey(id)] = os.time()
        saveVisits(visits)
    end

    -- Query full pages and filter capacity locally. Some Roblox responses have
    -- returned an empty candidate set with excludeFullGames=true even while the
    -- game can still matchmake another instance. Scanning both sort directions
    -- also avoids depending on only one edge of a large server list.
    local function getPage(sortOrder, cursor, generation)
        if not alive(generation) then return nil, "cancelled" end
        local url = "https://games.roblox.com/v1/games/" .. tostring(PLACE)
            .. "/servers/Public?sortOrder=" .. tostring(sortOrder) .. "&limit=100"
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

    local function scanText(stats)
        if not stats then return "scan=?" end
        return string.format("rows=%d open=%d fresh=%d repeat=%d current=%d",
            stats.Rows or 0, stats.Open or 0, stats.Fresh or 0,
            stats.Repeated or 0, stats.Current or 0)
    end

    local function chooseFromSorted(rows)
        if #rows == 0 then return nil end

        -- Multiple EndHub clients often hop at the same moment. Spreading each
        -- account across the first few low-ping choices avoids both accounts
        -- racing for the exact same last slot while still preferring good ping.
        local bestPing = tonumber(rows[1].ping)
        local pool = 1
        for i = 2, math.min(#rows, 5) do
            local p = tonumber(rows[i].ping)
            if bestPing and p and p <= math.max(cfg.ServerHopPingTarget, bestPing + 35) then
                pool = i
            elseif not bestPing and i <= 3 then
                pool = i
            else
                break
            end
        end
        local index = ((tonumber(Player.UserId) or 0) % pool) + 1
        return rows[index]
    end

    local function chooseServer(generation)
        local visits = pruneVisits(readVisits())
        local fresh, repeated = {}, {}
        local seen = {}
        local stats = {Rows = 0, Open = 0, Fresh = 0, Repeated = 0, Current = 0, Pages = 0}

        for _, sortOrder in ipairs({"Asc", "Desc"}) do
            local cursor = nil
            for _ = 1, cfg.ServerHopPages do
                local page, err = getPage(sortOrder, cursor, generation)
                if not page then return nil, visits, false, err, stats end
                stats.Pages = stats.Pages + 1

                for _, server in ipairs(page.data) do
                    local id = type(server.id) == "string" and server.id or nil
                    if id and not seen[id] then
                        seen[id] = true
                        stats.Rows = stats.Rows + 1

                        local playing = tonumber(server.playing)
                        local maxPlayers = tonumber(server.maxPlayers)
                        if id == JOB then
                            stats.Current = stats.Current + 1
                        elseif playing and maxPlayers and maxPlayers > 0 and playing < maxPlayers then
                            stats.Open = stats.Open + 1
                            local row = {
                                id = id,
                                ping = tonumber(server.ping),
                                fps = tonumber(server.fps),
                                playing = playing,
                                maxPlayers = maxPlayers,
                                lastVisit = visits[visitKey(id)],
                            }
                            if row.lastVisit then repeated[#repeated + 1] = row
                            else fresh[#fresh + 1] = row end
                        end
                    end
                end

                cursor = page.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
            end
        end

        stats.Fresh = #fresh
        stats.Repeated = #repeated
        R.ServerHopScan = stats
        print("[EndHub HopScan] user=" .. tostring(Player.UserId) .. " | " .. scanText(stats))

        table.sort(fresh, better)
        local picked = chooseFromSorted(fresh)
        if picked then return picked, visits, false, nil, stats end

        -- Do not repeat during the TTL unless every open public candidate is in
        -- history. Then choose the least-recently visited server as a fallback.
        table.sort(repeated, function(a, b)
            if a.lastVisit ~= b.lastVisit then return (a.lastVisit or 0) < (b.lastVisit or 0) end
            return better(a, b)
        end)
        if #repeated > 0 then return repeated[1], visits, true, nil, stats end

        if stats.Rows == 0 then
            return nil, visits, false, "PUBLIC SERVER LIST EMPTY", stats
        elseif stats.Current > 0 and stats.Rows == stats.Current then
            return nil, visits, false, "ONLY CURRENT PUBLIC SERVER VISIBLE", stats
        elseif stats.Open == 0 then
            return nil, visits, false, "NO OTHER OPEN PUBLIC SERVER", stats
        end
        return nil, visits, false, "NO DIRECT SERVER CANDIDATE", stats
    end

    local function waitForTeleport(generation, seconds)
        local deadline = tick() + seconds
        while alive(generation) and not R.HopFailed and tick() < deadline do task.wait(0.25) end
        if not alive(generation) then return true end
        return false
    end

    local function directTeleport(selected, visits, repeated, generation, attempt)
        R.HopFailed, R.HopError = false, nil
        R.TargetServer = selected.id
        markVisited(visits, selected.id)

        local pingText = selected.ping and (tostring(math.floor(selected.ping + 0.5)) .. "ms") or "ping?"
        local fpsText = selected.fps and (tostring(math.floor(selected.fps + 0.5)) .. "fps") or "fps?"
        status(string.format("TELEPORTING LOW PING %s | %s | %s | %d/%d | TRY %d%s",
            selected.id, pingText, fpsText, selected.playing, selected.maxPlayers, attempt,
            repeated and " | REPEAT FALLBACK" or ""))

        local ok, errorMessage = pcall(function()
            Teleports:TeleportToPlaceInstance(PLACE, selected.id, Player)
        end)
        if not ok then
            R.HopFailed = true
            R.HopError = tostring(errorMessage)
            return false, R.HopError
        end

        if waitForTeleport(generation, 30) then return true end
        return false, R.HopError or "DIRECT TELEPORT NOT COMPLETED"
    end

    local function matchmakerTeleport(generation, attempt, reason, stats)
        -- If the public list exposes no usable *other* instance, ask Roblox's
        -- own matchmaker for this place instead of freezing the farm for a minute.
        -- Ping/repeat preference cannot be guaranteed in this fallback because
        -- Roblox chooses the destination, but it keeps the server cycle moving.
        R.HopFailed, R.HopError = false, nil
        R.TargetServer = nil
        status("MATCHMAKER FALLBACK | " .. tostring(reason) .. " | " .. scanText(stats) .. " | TRY " .. attempt)

        local ok, errorMessage = pcall(function()
            Teleports:Teleport(PLACE, Player)
        end)
        if not ok then
            R.HopFailed = true
            R.HopError = tostring(errorMessage)
            return false, R.HopError
        end

        if waitForTeleport(generation, 30) then return true end
        return false, R.HopError or "MATCHMAKER TELEPORT NOT COMPLETED"
    end

    local oldRequestHop = R.RequestHop
    R.RequestHop = function(reason)
        if not alive() or R.Hopping then return false end
        R.Hopping = true
        R.HopOwned = true
        R.Failed = false

        -- Match the cycle's pause behavior without touching its private locals.
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

                local selected, currentVisits, repeated, err, stats = chooseServer(generation)
                if not alive(generation) then return end

                local completed, teleportError
                if selected then
                    completed, teleportError = directTeleport(selected, currentVisits, repeated, generation, attempt)
                else
                    completed, teleportError = matchmakerTeleport(generation, attempt, err or "NO DIRECT SERVER", stats)
                end
                if completed then return end
                lastError = teleportError or err or lastError

                if alive(generation) and attempt < 3 then
                    status("HOP RETRY: " .. tostring(lastError) .. " | RESCANNING")
                    task.wait(4 + math.random())
                end
            end

            if alive(generation) then
                R.Hopping = false
                R.HopOwned = false
                R.Failed = true
                R.TargetServer = nil
                R.HopRetryAt = tick() + 30 + math.random(0, 15)
                status("HOP PAUSED: " .. tostring(lastError) .. " | AUTO RETRY IN 30-45s")
            end
        end)
        return true
    end

    H.ServerHop = H.ServerHop or {}
    H.ServerHop.Request = R.RequestHop
    R.QualityHopPatchInstalled = true
    R.OriginalRequestHop = oldRequestHop
    print(string.format("[EndHub] quality server hop v2 loaded | visited TTL=%ds | pages=%d x 2 orders | low-ping spread + matchmaker fallback",
        cfg.ServerHopVisitedResetSeconds, cfg.ServerHopPages))
end
