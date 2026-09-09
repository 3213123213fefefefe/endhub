-- One owner per Roblox client. AutoExecute + teleport queue share this guard;
-- separate Roblox processes never depend on each other's files or input.
local ENV = getgenv()
local JOB, VERSION = tostring(game.JobId), "multi-client-8"
local boot = ENV.ENDHUB_BOOT
if boot and boot.JobId == JOB and boot.Loading then
    while boot.Loading and ENV.ENDHUB_BOOT == boot do task.wait(0.1) end
    if boot.Hub then return boot.Hub end
    error(boot.Error or "[EndHub] concurrent initialization failed", 0)
end
local live = ENV.ENDHUB
if live and live.JobId == JOB and live.WorkBuild == VERSION and live.State
    and live.State.Ready and not live.State.Unloaded and live.ServerCycle then return live end
if live and live.Unload then pcall(function() live:Unload() end) end
boot = {JobId = JOB, Loading = true}
ENV.ENDHUB_BOOT = boot
ENV.ENDHUB_WORK_LOADING = true
local ok, result = pcall(function()
    while not game:IsLoaded() or not game:GetService("Players").LocalPlayer do task.wait(0.1) end
    local repo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/"
    local function fetch(path)
        local source = game:HttpGet(repo .. path .. "?v=" .. tostring(os.time()))
        local fn, err = loadstring(source, "EndHub " .. path)
        assert(fn, err)
        return fn()
    end
    local hub = fetch("EndHub.lua")
    -- Keep the working server/farm improvements and the restored legacy
    -- Potassium teleport queue behavior. Server-hop coordination is independent.
    for _, path in ipairs({"modules/fps_patch.lua", "modules/server_cycle.lua",
        "modules/legacy_autoload_patch.lua", "modules/menu_first_screen_patch.lua",
        "modules/server_hop_quality_patch.lua"}) do
        fetch(path)(hub)
    end
    assert(hub.ServerCycle and hub.ServerCycle.MenuStep, "[EndHub] cycle missing")
    hub.WorkBuild = VERSION
    hub.State.Ready = true
    hub.ServerCycle.Bootstrap()
    print("[EndHub Loader] " .. VERSION .. " | account=" .. tostring(hub.S.Player.UserId))
    return hub
end)
ENV.ENDHUB_WORK_LOADING = nil
boot.Loading = false
if not ok then
    boot.Error = tostring(result)
    local partial = ENV.ENDHUB
    if partial and partial.Unload then pcall(function() partial:Unload() end) end
    if partial and partial.State then partial.State.Unloaded = true end
    ENV.ENDHUB, ENV.ENDHUB_BOOT = nil, nil
    error(result, 0)
end
boot.Hub = result
return result
