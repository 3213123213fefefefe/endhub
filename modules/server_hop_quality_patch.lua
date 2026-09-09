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
    local USER = tostring(Player.UserId)
    local visitedFile = H.Persistence and H.Persistence.VisitedFile or "EndHub/serverhop_visited.json"
    local claimFile = "EndHub/serverhop_claims_" .. tostring(PLACE) .. ".json"
    local CLAIM_TTL = 35

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

    -- Local clients normally share the executor workspace. This tiny claim file
    -- lets them reserve different destinations without merging account profiles.
    local function readClaims()
        local claims = C.ReadJson(claimFile)
        return type(claims) == "table" and claims or {}
    end

    local function pruneClaims(claims)
        local now = os.time()
        local changed = false
        for id, row in pairs(claims) do
            if type(row) ~= "table" or type(row.t) ~= "number" or now - row.t >= CLAIM_TTL then
                claims[id] = nil
                changed = true
            end
        end
        if changed then C.WriteJson(claimFile, claims) end
        return claims
    end

    local function claimedByOther(id, claims)
        local row = claims and claims[tostring(id)]
        return type(row) == "table" and tostring(row.user or "") ~= USER
    end

    local function refreshPresence()
        if JOB == "" then return end
        local claims = pruneClaims(readClaims())
        claims[JOB] = {user = USER, t = os.time()}
        C.WriteJson(claimFile, claims)
    end

    local function releaseClaim(id)
        if not id then return end
        local claims = pruneClaims(readClaims())
        local row = claims[tostring(id)]
        if type(row) == "table" and tostring(row.user or "") == USER then
            claims[tostring(id)] = nil
            C.WriteJson(claimFile, claims)
        end
    end

    local function claimServer(id)
        id = tostring(id or "")
        if id == "" then return false, "invalid-server" end

        local claims = pruneClaims(readClaims())
        local existing = claims[id]
        if type(existing) == "table" and tostring(existing.user or "") ~= USER then
            return false, tostring(existing.user or "other")
        end

        claims[id] = {user = USER, t = os.time()}
        C.WriteJson(claimFile, claims)

        -- Resolve near-simultaneous writes by re-reading after a short settle.
        task.wait(0.12 + ((tonumber(Player.UserId) or 0) % 5) * 0.025)
        local verify = pruneClaims(readClaims())
        local owner = verify[id]
        if type(owner) == "table" and tostring(owner.user or "") == USER then
            return true
        end
        return false, type(owner) == "table" and tostring(owner.user or "other") or "claim-lost"
    end

    refreshPresence()
    task.spawn(function()
        while not H.State.Unloaded do
            task.wait(10)
            if alive() then pcall(refreshPresence) end
        end
    end)

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
        return string.format("rows=%d open=%d fresh=%d repeat=%d current=%d claimed=%d",
            stats.Rows or 0, stats.Open or 0, stats.Fresh or 0,
            stats.Repeated or 0, stats.Current or 0, stats.Claimed or 0)
    end

    local function chooseFromSorted(rows)
        if #rows == 0 then return nil end

        -- Prefer good ping, but use a broader top pool so local accounts do not
        -- deterministically converge on the same one or two servers.
        local bestPing = tonumber(rows[1].ping)
        local pool = math.min(#rows, 8)
        if bestPing then
            local limited = 1
            for i = 2, pool do
                local p = tonumber(rows[i].ping)
                if p and p <= math.max(cfg.ServerHopPingTarget + 40, bestPing + 70) then
                    limited = i
                else
                    break
                end
            end
            pool = math.max(1, limited)
        end

        local uid = tonumber(Player.UserId) or 0
        local mixed = math.floor(uid / 4) + math.floor(uid / 97) * 3 + math.floor(uid / 997) * 7
        local index = (mixed % pool) + 1
        return rows[index]
    end

    local function chooseServer(generation)
        local visits = pruneVisits(readVisits())
        local claims = pruneClaims(readClaims())
        local fresh, repeated = {}, {}
        local seen = {}
        local stats = {Rows = 0, Open = 0, Fresh = 0, Repeated = 0, Current = 0, Claimed = 0, Pages = 0}

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
                            if claimedByOther(id, claims) then
                                stats.Claimed = stats.Claimed + 1
                            else
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
                end

                cursor = page.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
            end
        end

        stats.Fresh = #fresh
        stats.Repeated = #repeated
        R.ServerHopScan = stats
        print("[EndHub HopScan] user=" .. USER .. " | " .. scanText(stats))

        table.sort(fresh, better)
        local picked = chooseFromSorted(fresh)
        if picked then return picked, visits, false, nil, stats end

        table.sort(repeated, function(a, b)
            if a.lastVisit ~= b.lastVisit then return (a.lastVisit or 0) < (b.lastVisit or 0) end
            return better(a, b)
        end)
        if #repeated > 0 then return repeated[1], visits, true, nil, stats end

        if stats.Open > 0 and stats.Claimed >= stats.Open then
            return nil, visits, false, "ALL OPEN SERVERS CLAIMED LOCALLY", stats
        elseif stats.Rows == 0 then
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
        local claimed, owner = claimServer(selected.id)
        if not claimed then
            return false, "SERVER CLAIM COLLISION WITH LOCAL BOT " .. tostring(owner)
        end

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
            releaseClaim(selected.id)
            return false, R.HopError
        end

        if waitForTeleport(generation, 30) then return true end
        releaseClaim(selected.id)
        return false, R.HopError or "DIRECT TELEPORT NOT COMPLETED"
    end

    local function matchmakerTeleport(generation, attempt, reason, stats)
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

        refreshPresence()
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
                elseif err == "ALL OPEN SERVERS CLAIMED LOCALLY" then
                    teleportError = err
                    status("HOP WAIT: " .. err .. " | " .. scanText(stats))
                else
                    completed, teleportError = matchmakerTeleport(generation, attempt, err or "NO DIRECT SERVER", stats)
                end
                if completed then return end
                lastError = teleportError or err or lastError

                if alive(generation) and attempt < 3 then
                    status("HOP RETRY: " .. tostring(lastError) .. " | RESCANNING")
                    task.wait(3 + ((tonumber(Player.UserId) or 0) % 7) * 0.18 + math.random())
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
    print(string.format("[EndHub] quality server hop v3 loaded | visited TTL=%ds | local claims=%ds | low-ping spread",
        cfg.ServerHopVisitedResetSeconds, CLAIM_TTL))
end
