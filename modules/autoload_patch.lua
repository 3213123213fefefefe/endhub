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

    function R.QueueBootstrap()
        if not R.Enabled then return false end
        intent(true)

        if type(queueFunction) ~= "function" then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub AutoLoad] queue_on_teleport unavailable; keep loader.lua in Potassium AutoExecute")
            return false
        end

        -- Do not permanently suppress a second queue attempt in the same job.
        -- A failed teleport can consume/drop an executor queue entry. We only
        -- debounce calls made almost simultaneously.
        local now = tick()
        if ENV.ENDHUB_QUEUE_JOB == JOB and now - (ENV.ENDHUB_QUEUE_AT or 0) < 1.5 then
            R.Continuity = "TELEPORT QUEUED"
            return true
        end

        local code = string.format([=[
local expectedUser, sourceJob, loaderURL = %s, %q, %q
local Players = game:GetService("Players")

-- Some executors start queued code while the old DataModel/JobId is still
-- visible. Wait for the destination job instead of returning immediately.
local deadline = tick() + 25
while (not Players.LocalPlayer or tostring(game.JobId) == sourceJob) and tick() < deadline do
    task.wait(0.10)
end

local player = Players.LocalPlayer
if not player or player.UserId ~= expectedUser then return end
if tostring(game.JobId) == sourceJob then
    warn("[EndHub AutoLoad] destination job was not observed; queued load cancelled")
    return
end

while not game:IsLoaded() do task.wait(0.10) end

-- Give PlayerGui/replication a brief moment to exist before loading EndHub.
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

print("[EndHub AutoLoad] destination detected | user=" .. tostring(player.UserId) .. " | job=" .. tostring(game.JobId))
local ran, runErr = pcall(fn)
if not ran then warn("[EndHub AutoLoad] loader runtime failed: " .. tostring(runErr)) end
]=], tostring(Player.UserId), JOB, loaderURL)

        local ok, err = pcall(queueFunction, code)
        if not ok then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub AutoLoad] teleport queue failed: " .. tostring(err))
            return false
        end

        ENV.ENDHUB_QUEUE_JOB = JOB
        ENV.ENDHUB_QUEUE_AT = now
        ENV.ENDHUB_QUEUED_JOB = JOB -- compatibility with older cycle diagnostics
        R.Continuity = "TELEPORT QUEUED"
        print("[EndHub AutoLoad] queued | user=" .. tostring(Player.UserId) .. " | sourceJob=" .. JOB)
        return true
    end

    R.AutoLoadPatchInstalled = true
    print("[EndHub] teleport autoload patch loaded | waits for destination JobId")
end
