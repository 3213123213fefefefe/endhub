return function(H)
    local R = H.ServerCycle
    if not R or R.AutoLoadPatchInstalled then return end

    local ENV = getgenv()
    local Player = H.S.Player
    local Teleports = game:GetService("TeleportService")
    local SETTING = "EndHubServerCycleV1"
    local PLACE = game.PlaceId
    local JOB = tostring(game.JobId)
    local loaderURL = H.Repo .. "loader.lua"
    local WATCH_SECONDS = 20
    local REQUEUE_DELAY = 20.5

    local queueFunction = queue_on_teleport or queueonteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

    local function intent(enabled)
        pcall(function()
            Teleports:SetTeleportSetting(SETTING, {
                Enabled = enabled,
                PlaceId = PLACE,
                UserId = Player.UserId,
                SourceJob = JOB,
            })
        end)
    end

    local function sameSourceJob()
        return tostring(game.JobId) == JOB
            and H.State and not H.State.Unloaded
            and R.Enabled
    end

    function R.QueueBootstrap()
        if not R.Enabled then return false end
        intent(true)

        if type(queueFunction) ~= "function" then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub AutoLoad] queue_on_teleport unavailable; keep loader.lua in Potassium AutoExecute")
            return false
        end

        -- Keep one short-lived watcher at a time. If a hop is still in progress
        -- after 20 seconds, the source client queues a fresh watcher automatically.
        local now = tick()
        if ENV.ENDHUB_QUEUE_JOB == JOB and now - (ENV.ENDHUB_QUEUE_AT or 0) < (WATCH_SECONDS + 2) then
            R.Continuity = "TELEPORT QUEUED"
            return true
        end

        local code = string.format([=[
local expectedUser, sourceJob, loaderURL, watchSeconds = %s, %q, %q, %s
local Players = game:GetService("Players")

local startedAt = tick()
local deadline = startedAt + watchSeconds
local announcedWait = false

while tick() < deadline do
    local player = Players.LocalPlayer
    local currentJob = tostring(game.JobId)

    if player and player.UserId ~= expectedUser then
        warn("[EndHub AutoLoad] queued watcher landed on another account; cancelled")
        return
    end

    if player and currentJob ~= sourceJob then
        while not game:IsLoaded() do task.wait(0.10) end
        task.wait(0.35)

        local ok, source = pcall(function()
            return game:HttpGet(loaderURL .. "?v=" .. tostring(os.time()) .. "-" .. tostring(math.random(100000,999999)))
        end)
        if not ok or type(source) ~= "string" then
            warn("[EndHub AutoLoad] loader download failed: " .. tostring(source))
            return
        end

        local fn, err = loadstring(source)
        if not fn then
            warn("[EndHub AutoLoad] loader compile failed: " .. tostring(err))
            return
        end

        print("[EndHub AutoLoad] destination detected | user=" .. tostring(player.UserId) .. " | job=" .. currentJob)
        local ran, runErr = pcall(fn)
        if not ran then warn("[EndHub AutoLoad] loader runtime failed: " .. tostring(runErr)) end
        return
    end

    if not announcedWait and tick() - startedAt >= 1 then
        announcedWait = true
        print("[EndHub AutoLoad] queue callback started in source job | waiting up to " .. tostring(watchSeconds) .. "s for destination")
    end
    task.wait(0.10)
end

warn("[EndHub AutoLoad] destination job was not observed after " .. tostring(watchSeconds) .. "s; watcher expired")
]=], tostring(Player.UserId), JOB, loaderURL, tostring(WATCH_SECONDS))

        local ok, err = pcall(queueFunction, code)
        if not ok then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub AutoLoad] teleport queue failed: " .. tostring(err))
            return false
        end

        ENV.ENDHUB_QUEUE_JOB = JOB
        ENV.ENDHUB_QUEUE_AT = now
        ENV.ENDHUB_QUEUED_JOB = JOB
        R.Continuity = "TELEPORT QUEUED"
        print("[EndHub AutoLoad] watcher queued | user=" .. tostring(Player.UserId) .. " | sourceJob=" .. JOB .. " | ttl=" .. WATCH_SECONDS .. "s")

        -- Queue again only while this client is genuinely still trying to hop.
        -- This avoids a permanent background loop during ordinary farming.
        if R.Hopping and not R.AutoLoadRetryScheduled then
            R.AutoLoadRetryScheduled = true
            task.delay(REQUEUE_DELAY, function()
                R.AutoLoadRetryScheduled = false
                if not sameSourceJob() or not R.Hopping then return end
                ENV.ENDHUB_QUEUE_AT = 0
                print("[EndHub AutoLoad] destination not reached yet | retrying queue after 20s")
                R.QueueBootstrap()
            end)
        end

        return true
    end

    R.AutoLoadPatchInstalled = true
    print("[EndHub] teleport autoload patch v3 loaded | 20s watcher + automatic retry while hopping")
end
