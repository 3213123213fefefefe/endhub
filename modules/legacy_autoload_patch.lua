return function(H)
    local R = H.ServerCycle
    if not R or R.LegacyAutoLoadPatchInstalled then return end

    local ENV = getgenv()
    local Teleports = game:GetService("TeleportService")
    local SETTING = "EndHubServerCycleV1"
    local PLACE = game.PlaceId
    local JOB = tostring(game.JobId)
    local loaderURL = H.Repo .. "loader.lua"

    local queueFunction = queue_on_teleport or queueonteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

    local function intent(enabled)
        pcall(function()
            Teleports:SetTeleportSetting(SETTING, {Enabled = enabled, PlaceId = PLACE})
        end)
    end

    -- Restored from the pre multi-client-2 behavior that was confirmed working
    -- with Potassium: queue the loader and let the executor deliver it on teleport.
    -- Do not inspect source/destination JobId inside the queued callback.
    function R.QueueBootstrap()
        if not R.Enabled then return false end
        intent(true)

        if ENV.ENDHUB_QUEUED_JOB == JOB then
            R.Continuity = "TELEPORT QUEUED"
            return true
        end

        if type(queueFunction) ~= "function" then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub Cycle] queue_on_teleport unavailable; keep loader.lua in executor AutoExecute")
            return false
        end

        local code = string.format([=[
local ok, data = pcall(function()
    return game:GetService("TeleportService"):GetTeleportSetting(%q)
end)
-- Loading again always starts a fresh cycle, even if the previous session was stopped.
local source = game:HttpGet(%q .. "?v=" .. tostring(os.time()))
local fn, err = loadstring(source)
assert(fn, err)
fn()
]=], SETTING, loaderURL)

        local ok, err = pcall(queueFunction, code)
        if not ok then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub Cycle] teleport queue failed: " .. tostring(err))
            return false
        end

        ENV.ENDHUB_QUEUED_JOB = JOB
        R.Continuity = "TELEPORT QUEUED"
        print("[EndHub Cycle] legacy teleport queue armed | job=" .. JOB)
        return true
    end

    R.LegacyAutoLoadPatchInstalled = true
    print("[EndHub] legacy teleport autoload restored | pre multi-client-2 behavior")
end
