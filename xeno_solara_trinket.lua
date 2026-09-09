-- EndHub Xeno/Solara compatibility build
-- Standalone trinket route bot with minimal executor dependencies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
while not player do task.wait(0.1) player = Players.LocalPlayer end
while not game:IsLoaded() do task.wait(0.1) end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.ENDHUB_XS and ENV.ENDHUB_XS.Unload then pcall(ENV.ENDHUB_XS.Unload) end

local Bot = {
    Running = false,
    Route = {},
    RouteIndex = 1,
    Status = "IDLE",
    PickupDistance = 7,
    PointWait = 0.8,
    TargetTimeout = 12,
    RouteRadius = 140,
    AutoHop = true,
    Hopping = false,
    Connections = {},
}
ENV.ENDHUB_XS = Bot

local function executorName()
    if type(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and name then return tostring(name) end
    end
    if type(getexecutorname) == "function" then
        local ok, name = pcall(getexecutorname)
        if ok and name then return tostring(name) end
    end
    return "Unknown"
end

local function root()
    local ch = player.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function setNoclip(active)
    local ch = player.Character
    if not ch then return end
    if active then
        for _, p in ipairs(ch:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end

local function teleport(pos)
    local r = root()
    if not r then return false end
    r.CFrame = CFrame.new(pos)
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    return true
end

local function dropsFolder()
    return workspace:FindFirstChild("Drops")
end

local function dropPart(m)
    if not m or not m.Parent then return nil end
    return m:FindFirstChild("Handle") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end

local function validDrop(m)
    return m and m:IsA("Model") and m:FindFirstChild("AtTrinketSpawn") ~= nil
        and m:FindFirstChild("IsInteractable") ~= nil and dropPart(m) ~= nil
end

local function nearestDrop(center, radius)
    local folder = dropsFolder()
    if not folder then return nil end
    local best, bestD
    for _, m in ipairs(folder:GetChildren()) do
        if validDrop(m) then
            local p = dropPart(m)
            local d = (p.Position - center).Magnitude
            if d <= radius and (not bestD or d < bestD) then best, bestD = m, d end
        end
    end
    return best
end

local function pickupRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("InteractPromptEvent")
    if remote and remote:IsA("RemoteEvent") then return remote end
    return nil
end

local function pickup(target)
    local p = dropPart(target)
    if not p then return false end
    local r = root()
    if not r then return false end
    if (r.Position - p.Position).Magnitude > Bot.PickupDistance then
        teleport(p.Position + Vector3.new(0, 2.5, 0))
        task.wait(0.05)
    end
    local remote = pickupRemote()
    if not remote then
        Bot.Status = "NO PICKUP REMOTE"
        return false
    end
    local started = tick()
    while Bot.Running and target.Parent and tick() - started < Bot.TargetTimeout do
        pcall(function() remote:FireServer("PickupDrop", target) end)
        task.wait(0.25)
    end
    return not target.Parent
end

local dir = "EndHub_XenoSolara"
local routeFile = dir .. "/route_" .. tostring(game.PlaceId) .. ".json"
local fsOK = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local function ensureDir()
    if type(isfolder) == "function" and type(makefolder) == "function" then
        local ok, exists = pcall(isfolder, dir)
        if ok and not exists then pcall(makefolder, dir) end
    end
end

local function saveRoute()
    if not fsOK then Bot.Status = "ROUTE MEMORY ONLY" return false end
    ensureDir()
    local out = {}
    for i, v in ipairs(Bot.Route) do out[i] = {v.X, v.Y, v.Z} end
    local ok, raw = pcall(HttpService.JSONEncode, HttpService, out)
    if ok then
        local wrote = pcall(writefile, routeFile, raw)
        Bot.Status = wrote and "ROUTE SAVED" or "SAVE FAILED"
        return wrote
    end
    return false
end

local function loadRoute()
    if not fsOK then return end
    local okExists, exists = pcall(isfile, routeFile)
    if not okExists or not exists then return end
    local okRead, raw = pcall(readfile, routeFile)
    if not okRead then return end
    local okJson, rows = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okJson or type(rows) ~= "table" then return end
    Bot.Route = {}
    for _, row in ipairs(rows) do
        if type(row) == "table" and tonumber(row[1]) and tonumber(row[2]) and tonumber(row[3]) then
            Bot.Route[#Bot.Route + 1] = Vector3.new(row[1], row[2], row[3])
        end
    end
end
loadRoute()

local function queueFn()
    if type(queue_on_teleport) == "function" then return queue_on_teleport end
    if type(queueonteleport) == "function" then return queueonteleport end
    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then return syn.queue_on_teleport end
    return nil
end

-- Reload the combined XS loader after a successful teleport so the Solara
-- menu helper is also restored, not only the trinket loop.
local branchLoader = [[loadstring(game:HttpGet("https://raw.githubusercontent.com/3213123213fefefefe/endhub/compat-xeno-solara/xs_loader.lua?v=" .. tostring(os.time())))()]]

local visitedServers = {[tostring(game.JobId)] = true}

local function getServerCandidates()
    local rows, cursor = {}, nil
    for _ = 1, 4 do
        local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
            .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
        local ok, raw = pcall(function() return game:HttpGet(url) end)
        if not ok or type(raw) ~= "string" then break end
        local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not decodedOk or type(data) ~= "table" or type(data.data) ~= "table" then break end
        for _, server in ipairs(data.data) do
            local id = tostring(server.id or "")
            local playing = tonumber(server.playing)
            local maxPlayers = tonumber(server.maxPlayers)
            if id ~= "" and id ~= tostring(game.JobId) and not visitedServers[id]
                and playing and maxPlayers and playing < maxPlayers then
                rows[#rows + 1] = {
                    id = id,
                    playing = playing,
                    maxPlayers = maxPlayers,
                    ping = tonumber(server.ping) or math.huge,
                    fps = tonumber(server.fps) or 0,
                }
            end
        end
        cursor = data.nextPageCursor
        if type(cursor) ~= "string" or cursor == "" then break end
    end
    table.sort(rows, function(a, b)
        if a.ping ~= b.ping then return a.ping < b.ping end
        if a.fps ~= b.fps then return a.fps > b.fps end
        return a.playing < b.playing
    end)
    return rows
end

local function hop()
    if Bot.Hopping then return false end
    Bot.Hopping = true
    local wasRunning = Bot.Running
    Bot.Running = false

    local q = queueFn()
    if q then
        local okQueue, errQueue = pcall(q, branchLoader)
        if not okQueue then
            warn("[EndHub XS Hop] queue failed: " .. tostring(errQueue))
            q = nil
        end
    end

    local candidates = getServerCandidates()
    print(string.format("[EndHub XS Hop] candidates=%d | queue=%s | current=%s",
        #candidates, q and "OK" or "NO", tostring(game.JobId)))

    if #candidates == 0 then
        Bot.Status = "HOP FAILED - NO SERVER"
        Bot.Hopping = false
        Bot.Running = wasRunning
        return false
    end

    for attempt = 1, math.min(4, #candidates) do
        local target = candidates[attempt]
        visitedServers[target.id] = true
        Bot.Status = string.format("HOP %d -> %s", attempt, target.id:sub(1, 8))
        print(string.format("[EndHub XS Hop] TELEPORT try=%d server=%s ping=%s playing=%d/%d",
            attempt, target.id, tostring(target.ping), target.playing, target.maxPlayers))

        local failed = false
        local failMessage = nil
        local failConn
        failConn = TeleportService.TeleportInitFailed:Connect(function(plr, result, message, placeId)
            if plr == player and tonumber(placeId) == tonumber(game.PlaceId) then
                failed = true
                failMessage = tostring(result) .. " | " .. tostring(message)
            end
        end)

        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, player)
        end)
        if not ok then
            failed = true
            failMessage = tostring(err)
        end

        local deadline = tick() + 8
        while ENV.ENDHUB_XS == Bot and not failed and tick() < deadline do task.wait(0.2) end
        if failConn then pcall(function() failConn:Disconnect() end) end

        if failed then
            warn("[EndHub XS Hop] failed try=" .. attempt .. " | " .. tostring(failMessage))
            task.wait(0.8)
        else
            -- If this VM is still alive after the deadline, the teleport did not
            -- complete. Try another direct instance instead of silently stopping.
            warn("[EndHub XS Hop] no destination observed; trying another server")
        end
    end

    Bot.Status = q and "HOP FAILED - RETRY" or "HOP FAILED - RERUN AFTER HOP"
    Bot.Hopping = false
    Bot.Running = wasRunning
    return false
end
Bot.Hop = hop

local guiParent = CoreGui
if type(gethui) == "function" then
    local ok, hui = pcall(gethui)
    if ok and hui then guiParent = hui end
end

local gui = Instance.new("ScreenGui")
gui.Name = "EndHub_XenoSolara"
gui.ResetOnSpawn = false
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(300, 300)
frame.Position = UDim2.fromOffset(25, 150)
frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,32)
title.BackgroundTransparency = 1
title.Text = "EndHub XS | " .. executorName()
title.TextColor3 = Color3.new(1,1,1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 16
title.Parent = frame

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(8,34)
status.Size = UDim2.new(1,-16,0,52)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(220,220,220)
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.Code
status.TextSize = 13
status.Parent = frame

local function button(text, y, fn)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(8,y)
    b.Size = UDim2.new(1,-16,0,30)
    b.BackgroundColor3 = Color3.fromRGB(38,38,38)
    b.TextColor3 = Color3.new(1,1,1)
    b.Text = text
    b.Font = Enum.Font.Code
    b.TextSize = 14
    b.Parent = frame
    b.MouseButton1Click:Connect(fn)
    return b
end

button("START / STOP BOT", 90, function()
    if Bot.Hopping then return end
    Bot.Running = not Bot.Running
    Bot.Status = Bot.Running and "STARTED" or "STOPPED"
end)
button("ADD ROUTE POINT HERE", 126, function()
    local r = root()
    if r then
        Bot.Route[#Bot.Route + 1] = r.Position
        Bot.Status = "POINT ADDED #" .. tostring(#Bot.Route)
        saveRoute()
    end
end)
button("SAVE ROUTE", 162, saveRoute)
button("CLEAR ROUTE", 198, function()
    Bot.Route = {}
    Bot.RouteIndex = 1
    Bot.Status = "ROUTE CLEARED"
    saveRoute()
end)
button("SERVER HOP NOW", 234, function() task.spawn(hop) end)

local runningThread = false
local function botLoop()
    if runningThread then return end
    runningThread = true
    task.spawn(function()
        while ENV.ENDHUB_XS == Bot do
            if Bot.Hopping then task.wait(0.2) continue end
            if not Bot.Running then task.wait(0.2) continue end
            if #Bot.Route == 0 then Bot.Status = "NO ROUTE POINTS" task.wait(0.5) continue end
            if Bot.RouteIndex > #Bot.Route then Bot.RouteIndex = 1 end
            local point = Bot.Route[Bot.RouteIndex]
            Bot.Status = string.format("POINT %d/%d", Bot.RouteIndex, #Bot.Route)
            teleport(point)
            task.wait(Bot.PointWait)
            local foundAny = false
            while Bot.Running and not Bot.Hopping do
                local target = nearestDrop(point, Bot.RouteRadius)
                if not target then break end
                foundAny = true
                local p = dropPart(target)
                if p then teleport(p.Position + Vector3.new(0,2.5,0)) task.wait(0.05) end
                Bot.Status = "PICKUP " .. target.Name
                pickup(target)
                task.wait(0.12)
            end
            Bot.RouteIndex += 1
            if Bot.RouteIndex > #Bot.Route then
                Bot.RouteIndex = 1
                if Bot.AutoHop and not foundAny then
                    task.wait(1)
                    hop()
                    task.wait(1)
                end
            end
            task.wait(0.05)
        end
        runningThread = false
    end)
end
botLoop()

local noclipConn = RunService.Stepped:Connect(function()
    if Bot.Running then setNoclip(true) end
end)
Bot.Connections[#Bot.Connections+1] = noclipConn

task.spawn(function()
    while ENV.ENDHUB_XS == Bot and gui.Parent do
        status.Text = string.format("Status: %s\nRoute: %d points | point %d\nFS: %s | queue: %s",
            Bot.Status, #Bot.Route, Bot.RouteIndex, fsOK and "OK" or "MEMORY", queueFn() and "OK" or "NO")
        task.wait(0.25)
    end
end)

function Bot.Unload()
    Bot.Running = false
    Bot.Hopping = false
    for _, c in ipairs(Bot.Connections) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    if ENV.ENDHUB_XS == Bot then ENV.ENDHUB_XS = nil end
end

print(string.format("[EndHub XS] loaded | executor=%s | fs=%s | queue=%s | route=%d | direct-hop=v2",
    executorName(), fsOK and "OK" or "MEMORY", queueFn() and "OK" or "NO", #Bot.Route))
return Bot
