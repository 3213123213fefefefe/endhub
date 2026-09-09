-- Run from the repository root with Lua 5.4 or tests/run_lua_tests.py.
-- Roblox services and time are simulated; no real players, sales or teleports.
local output = print
local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end
local cycleSource = read("modules/server_cycle.lua")
local workSource = read("work_loader.lua")
local baseSource = read("EndHub.lua")
local routeSource = assert(workSource:match("local trinketExploreModule = %[%=+%[(.-)%]%=+%]"))
assert(load(cycleSource)); assert(load(workSource)); assert(load(baseSource)); assert(load(routeSource))
local function equal(actual, expected, message)
    assert(actual == expected, (message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function signal()
    local s = {connections = {}}
    function s:Connect(fn)
        local c = {Connected = true, Fn = fn}
        function c:Disconnect() self.Connected = false end
        self.connections[#self.connections + 1] = c
        return c
    end
    function s:Fire(...)
        local args = table.pack(...)
        for _, c in ipairs(self.connections) do
            if c.Connected then task.spawn(function() c.Fn(table.unpack(args, 1, args.n)) end) end
        end
    end
    return s
end
local function scheduler()
    local now, pending, seq = 0, {}, 0
    local function schedule(thread, delay)
        seq = seq + 1
        pending[#pending + 1] = {thread = thread, at = now + delay, seq = seq}
    end
    task = {}
    function task.spawn(fn) schedule(coroutine.create(fn), 0) end
    task.defer = task.spawn
    function task.delay(seconds, fn) schedule(coroutine.create(fn), seconds) end
    function task.wait(seconds) return coroutine.yield(seconds or 0.01) end
    tick = function() return now end
    return function(seconds)
        local target, iterations = now + seconds, 0
        while true do
            table.sort(pending, function(a, b) return a.at == b.at and a.seq < b.seq or a.at < b.at end)
            if not pending[1] or pending[1].at > target then break end
            local job = table.remove(pending, 1)
            now = job.at
            local ok, delay = coroutine.resume(job.thread)
            assert(ok, tostring(delay))
            if coroutine.status(job.thread) ~= "dead" then schedule(job.thread, delay) end
            iterations = iterations + 1
            assert(iterations < 100000, "scheduler did not make progress")
        end
        now = target
    end
end
local function context(options)
    options = options or {}
    local t = {advance = scheduler(), logs = {}, queries = {}, queued = {}, teleports = {}, starts = 0,
        moves = 0, saleSteps = 0, routeTeleports = 0, roles = options.roles or {}, loot = true,
        settings = options.settings or {}, disk = options.disk or {}, loaded = true, rootReady = true}
    local env = options.env or {}
    getgenv = function() return env end
    print = function(...) t.logs[#t.logs + 1] = table.concat({...}, " ") end
    warn = print
    Enum = {TeleportState = {Started = "Started", InProgress = "InProgress", Failed = "Failed"}}
    math.clamp = function(n, a, b) return math.max(a, math.min(n, b)) end
    Vector3 = {zero = {}, new = function(x, y, z) return {X = x, Y = y, Z = z} end}
    local players = {PlayerAdded = signal(), PlayerRemoving = signal(), list = {}}
    function players:GetPlayers() return self.list end
    function t:add(id, fire)
        local p = {UserId = id, Parent = players, OnTeleport = signal(), RequestStreamAroundAsync = function() end}
        players.list[#players.list + 1] = p
        if fire then players.PlayerAdded:Fire(p) end
        return p
    end
    function t:remove(p)
        p.Parent = nil
        for i, candidate in ipairs(players.list) do if candidate == p then table.remove(players.list, i) break end end
        players.PlayerRemoving:Fire(p)
    end
    local player = t:add(1)
    player.Character = {}
    t.humanoid = {Health = 100}
    local emptyGui = {GetDescendants = function() return {} end}
    player.FindFirstChild = function(_, name) if name == "PlayerGui" then return emptyGui end end
    players.LocalPlayer = player
    for _, id in ipairs(options.ids or {}) do t:add(id) end
    local groups = {}
    function groups:GetGroupInfoAsync(id)
        equal(id, 36025827)
        return {Roles = {{Name = "Tester", Rank = 252}}}
    end
    function groups:GetRolesInGroupAsync(id, group)
        equal(group, 36025827)
        t.queries[id] = (t.queries[id] or 0) + 1
        local entry = t.roles[id] or {name = "Member", rank = 1}
        if entry.delay then task.wait(entry.delay) end
        if entry.fail or entry.fallback then error("group API unavailable") end
        if entry.guest then return {IsMember = false, Roles = {}} end
        return {IsMember = true, Roles = entry.multiple or {{Name = entry.name, Rank = entry.rank}}}
    end
    function groups:GetGroupsAsync(id)
        local entry = t.roles[id] or {}
        if not entry.fallback then error("fallback unavailable") end
        return {{Id = 36025827, Role = entry.name, Rank = entry.rank}}
    end
    local teleports = {TeleportInitFailed = signal()}
    function teleports:SetTeleportSetting(key, value) t.settings[key] = value end
    function teleports:GetTeleportSetting(key) return t.settings[key] end
    function teleports:TeleportToPlaceInstance(place, server, who)
        equal(place, game.PlaceId); equal(who, player)
        t.teleports[#t.teleports + 1] = server
        player.OnTeleport:Fire(Enum.TeleportState.Started)
        if t.teleportFails then self.TeleportInitFailed:Fire(player, "Failure", "test failure", place) end
    end
    local http = {JSONDecode = function(_, value) return value end, UrlEncode = function(_, value) return value end}
    game = {PlaceId = 125503525638054, JobId = options.job or "current-job"}
    function game:IsLoaded() return t.loaded end
    function game:GetService(name)
        return ({Players = players, GroupService = groups, TeleportService = teleports})[name]
    end
    function game:HttpGet(url)
        assert(url:find("/servers/Public", 1, true), "unexpected HTTP request: " .. url)
        if t.httpFails then error("HTTP unavailable") end
        if t.serverResponse then return t.serverResponse(url) end
        return {data = {
            {id = game.JobId, playing = 1, maxPlayers = 20}, {id = "full", playing = 20, maxPlayers = 20},
            {id = "next-a", playing = 1, maxPlayers = 20}, {id = "next-b", playing = 1, maxPlayers = 20},
            {id = "next-c", playing = 1, maxPlayers = 20},
        }}
    end
    syn, fluxus, queueonteleport = nil, nil, nil
    queue_on_teleport = options.noQueue and nil or function(code) t.queued[#t.queued + 1] = code end
    if options.noQueue then queue_on_teleport = nil end
    local H = {Repo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/", Connections = {},
        S = {Players = players, Player = player, HttpService = http}, Config = options.config or {},
        State = {Ready = true, Unloaded = false, Running = false, FarmSellPhase = "FARM"}}
    H.Core = {
        Connect = function(s, fn) local c = s:Connect(fn) H.Connections[#H.Connections + 1] = c return c end,
        ReadJson = function(path) return t.disk[path] end,
        WriteJson = function(path, value) t.disk[path] = value return true end,
        Root = function() return t.rootReady and {} or nil end,
        Humanoid = function() return t.humanoid end,
        DropsFolder = function() return {} end, Noclip = function() end,
        Teleport = function() t.routeTeleports = t.routeTeleports + 1 return true end,
    }
    H.Farm = {
        Start = function() t.starts = t.starts + 1 H.State.Running = true end,
        Stop = function() H.State.Running = false H.State.CurrentTarget = nil end,
        Step = function() t.moves = t.moves + 1 end,
        Nearest = function() return t.loot and {} or nil end,
        Allowed = function(obj) return obj ~= nil and t.detected == true end,
        ClearTarget = function() H.State.CurrentTarget = nil end,
    }
    H.Sell = {Runtime = {}, Stop = function() H.Config.AutoSell = false H.Sell.Runtime.SellerTrip = nil end,
        Start = function() H.Config.AutoSell = true end,
        Step = function() t.saleSteps = t.saleSteps + 1 end, AutoFarmStep = function() t.saleSteps = t.saleSteps + 1 end}
    H.PersistenceManager = {SaveConfig = function() t.savedEnabled = H.Config.ServerCycleEnabled return true end}
    function H:Unload()
        self.State.Unloaded = true
        for _, c in ipairs(self.Connections) do c:Disconnect() end
    end
    if options.route then
        local group = setmetatable({}, {__index = function() return function() end end})
        H.UI = {Options = {}, Tabs = {Botting = {AddLeftGroupbox = function() return group end,
            AddRightGroupbox = function() return group end}}}
        H.Config.TrinketRoutes = {[tostring(game.PlaceId)] = {{10, 20, 30}, {40, 50, 60}}}
        assert(load(routeSource))()(H)
    end
    t.H, t.env, t.players, t.player, t.groups, t.service = H, env, players, player, groups, teleports
    t.R = assert(load(cycleSource))()(H)
    t.R.MenuEntered = true
    t.R.MenuClearSince = -10
    t.R.ReadyCharacter, t.R.CharacterReadyAt = player.Character, -1
    return t
end
local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end

test("waits for game, EndHub, character and every player; initializes once", function()
    local t = context({ids = {2, 3}, roles = {[2] = {name = "Member", rank = 1, delay = 3}, [3] = {guest = true}}})
    t.H.State.Ready, t.rootReady = false, false
    t.R.Bootstrap(); t.R.Bootstrap(); t.R.Start()
    equal(assert(load(cycleSource))()(t.H), t.R)
    equal(#t.H.Connections, 4)
    t.advance(1); equal(t.starts, 0); equal(t.queries[1], nil)
    t.H.State.Ready = true
    t.advance(2); equal(t.starts, 0)
    t.advance(3); equal(t.starts, 0)
    t.rootReady = true; t.advance(6)
    equal(t.starts, 1); equal(#t.queued, 1)
    for _, id in ipairs({1, 2, 3}) do equal(t.queries[id], 1) end
    assert(t.H.Config.AutoFarmSell)
end)

test("all listed roles, normalized names, higher ranks and local player trigger one hop", function()
    for _, role in ipairs({{"Tester", 252}, {"money tester", 253}, {"Admin", 254}, {"Owner", 255},
        {"  MONEY   TESTER  ", 0}, {"Renamed senior role", 253}}) do
        local t = context({ids = {2}, roles = {[1] = {name = role[1], rank = role[2]}, [2] = {name = "Owner", rank = 255}}})
        t.R.Bootstrap(); t.advance(2)
        equal(t.starts, 0); equal(#t.teleports, 1); equal(#t.queued, 1)
        equal(t.R.RequestHop("duplicate"), false)
        t.H.Farm.Start(); t.H.Farm.Step(); t.H.Sell.Start(); t.H.Sell.Step(); t.H.Sell.AutoFarmStep()
        equal(t.starts, 0); equal(t.moves, 0); equal(t.saleSteps, 0)
    end
end)

test("Member is ignored; multiple roles and fallback still detect Admin", function()
    local t = context()
    equal(t.R.IsRelevantRole("Member", 255), false)
    t.roles[1] = {multiple = {{Name = "Member", Rank = 1}, {Name = "Admin", Rank = 254}}}
    t.R.Bootstrap(); t.advance(2); equal(t.starts, 0); equal(#t.teleports, 1)
    t = context({roles = {[1] = {name = "Tester", rank = 252, fallback = true}}})
    t.R.Bootstrap(); t.advance(2); equal(t.starts, 0); equal(#t.teleports, 1)
end)

test("new arrivals pause immediately, resume only after checking, and stop sales for Admin", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1); equal(t.starts, 1)
    t.roles[2] = {name = "Member", rank = 1, delay = 2}
    local p = t:add(2, true)
    t.advance(0); equal(t.H.State.Running, false)
    t.H.Farm.Step(); equal(t.moves, 0)
    t.players.PlayerAdded:Fire(p); t.advance(3)
    equal(t.queries[2], 1); equal(t.starts, 2)
    t.H.Config.AutoSell, t.H.State.FarmSellPhase = true, "SELL"
    t.roles[3] = {name = "Admin", rank = 254}
    t:add(3, true); t.advance(1)
    equal(t.H.State.Running, false); equal(t.H.Config.AutoSell, false); equal(t.H.Config.AutoFarmSell, false)
    equal(#t.teleports, 1)
end)

test("departed players and results from stopped generations cannot trigger a hop", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    t.roles[2] = {name = "Admin", rank = 254, delay = 4}
    local p = t:add(2, true); t.advance(0.2); t:remove(p); t.advance(5)
    equal(#t.teleports, 0); assert(t.H.State.Running)
    t.roles[3] = {name = "Owner", rank = 255, delay = 4}
    t:add(3, true); t.advance(0.2); t.R.Stop(); t.advance(5)
    equal(#t.teleports, 0); equal(t.H.State.Running, false); equal(t.savedEnabled, false)
end)

test("a Member check preserves the existing sale and its return position", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    local trip = {Origin = "collection position", Character = "current character"}
    t.H.State.Running, t.H.Config.AutoSell, t.H.State.FarmSellPhase = false, true, "SELL"
    t.H.Sell.Runtime.SellerTrip = trip
    t.roles[2] = {name = "Member", rank = 1, delay = 1}
    t.roles[3] = {name = "Member", rank = 1, delay = 2}
    t:add(2, true); t:add(3, true); t.advance(0.1)
    equal(t.H.Config.AutoSell, false); equal(t.H.Sell.Runtime.SellerTrip, nil)
    t.advance(3)
    equal(t.H.Sell.Runtime.SellerTrip, trip); equal(t.H.State.FarmSellPhase, "SELL")
    equal(t.H.State.Running, false); assert(t.H.Config.AutoSell); equal(t.starts, 1)
end)

test("failed or timed-out checks never authorize loot; retry does not add connections", function()
    for _, entry in ipairs({{fail = true}, {name = "Owner", rank = 255, delay = 60}}) do
        local t = context({ids = {2}, roles = {[2] = entry}})
        t.R.Bootstrap(); t.advance(36)
        equal(t.starts, 0); equal(#t.teleports, 0); equal(t.R.Checks[t.players.list[2]].State, "unknown")
        t.roles[2] = {name = "Member", rank = 1}
        t.R.Retry(); t.advance(40)
        equal(t.starts, 1); equal(#t.teleports, 0); equal(#t.H.Connections, 4); equal(#t.queued, 1)
    end
end)

test("teleport failures retry different servers and eventually pause", function()
    local t = context()
    t.teleportFails = true
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(12)
    equal(#t.teleports, 3); equal(t.teleports[1], "next-a"); equal(t.teleports[2], "next-b")
    assert(t.R.Failed); equal(t.H.State.Running, false); equal(#t.queued, 1)
end)

test("server list failure remains paused and can be retried", function()
    local t = context()
    t.httpFails = true
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(12)
    assert(t.R.Failed); equal(#t.teleports, 0); equal(t.H.State.Running, false)
    t.httpFails = false; t.R.Retry(); t.advance(1); t.R.RequestHop("retry"); t.advance(1)
    equal(#t.teleports, 1)
end)

test("pagination skips current, full and recently visited servers", function()
    local t = context({disk = {["EndHub/serverhop_visited.json"] = {["125503525638054:visited"] = os.time()}}})
    t.serverResponse = function(url)
        if url:find("cursor=page2", 1, true) then return {data = {{id = "available", playing = 2, maxPlayers = 20}}} end
        return {data = {{id = "current-job", playing = 2, maxPlayers = 20}, {id = "full", playing = 20, maxPlayers = 20},
            {id = "visited", playing = 2, maxPlayers = 20}}, nextPageCursor = "page2"}
    end
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(1)
    equal(t.teleports[1], "available")
end)

test("only a complete empty lap hops; collecting repeats the route", function()
    local t = context({config = {ServerCycleIdleSeconds = 10}})
    t.R.Bootstrap(); t.advance(15); equal(#t.teleports, 0)
    t.loot = false; t.H.State.FarmSellPhase = "SELL"
    t.advance(15); equal(#t.teleports, 0)
    t.H.State.FarmSellPhase = "FARM"; t.advance(120); equal(#t.teleports, 0)
    t = context({route = true})
    t.loot = false
    t.H.Farm.Step(); equal(t.routeTeleports, 0)
    t.R.Bootstrap(); t.advance(1)
    t.H.Farm.Step(); equal(t.routeTeleports, 1)
    t:add(2, true); t.advance(0.3); t.H.Farm.Step()
    equal(t.routeTeleports, 1) -- A Member check cannot skip the remaining route wait.
    t.H.Farm.Step(); equal(#t.teleports, 0)
    t.advance(1.1); t.H.Farm.Step(); equal(t.routeTeleports, 2)
    t.H.State.LootPickupSerial = 1
    t.advance(1.1); t.H.Farm.Step(); t.advance(1)
    equal(#t.teleports, 0); equal(t.routeTeleports, 3)
    t.H.Farm.Step(); equal(t.routeTeleports, 4)
    t.advance(1.1); t.H.Farm.Step(); t.advance(1)
    equal(#t.teleports, 1); equal(t.routeTeleports, 4)
end)

test("matching detections keep the server even when pickup fails", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    t.detected = true
    assert(t.H.Farm.Allowed({}))
    t.detected = false -- The detection remains remembered for this entire lap.
    equal(t.R.OnLootComplete(), false); equal(#t.teleports, 0)
    equal(t.R.OnLootComplete(), true); t.advance(1); equal(#t.teleports, 1)
    t = context(); t.R.Bootstrap(); t.advance(1)
    t.detected = false; equal(t.H.Farm.Allowed({}), false)
    equal(t.R.OnLootComplete(), true); t.advance(1); equal(#t.teleports, 1)
end)

test("new load forces Play and farm-sell ON even after Stop or saved OFF", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    local settings, queued = t.settings, t.queued[1]
    t = context({job = "new-job", settings = settings, config = {ServerCycleEnabled = false}})
    t.R.Bootstrap(); equal(t.starts, 0); t.advance(1)
    equal(t.starts, 1); equal(t.queries[1], 1); equal(#t.queued, 1)
    t.R.Stop()
    local bootCalls = 0
    game.HttpGet = function() return "loader" end
    loadstring = function() return function() bootCalls = bootCalls + 1 end end
    assert(load(queued))()
    equal(bootCalls, 1)
    t.H.Config.ServerCycleEnabled, t.H.Config.ServerCycleAutoSell = false, false
    t.R.Bootstrap(); t.advance(1)
    assert(t.H.Config.AutoFarmSell); assert(t.H.State.Running)
    t.H:Unload()
    for _, c in ipairs(t.H.Connections) do equal(c.Connected, false) end
    t.advance(1); equal(t.H.State.Running, false)
end)

test("AutoExecute-only executors and external teleport failures remain manageable", function()
    local t = context({noQueue = true})
    t.R.Bootstrap(); t.advance(1)
    equal(t.R.Continuity, "AUTOEXEC REQUIRED"); equal(t.starts, 1)
    t.player.OnTeleport:Fire(Enum.TeleportState.Started); t.advance(0)
    t.service.TeleportInitFailed:Fire(t.player, "Failure", "external failure", game.PlaceId); t.advance(0)
    equal(t.R.Hopping, false); assert(t.R.Failed)
    t.R.Retry(); t.advance(1); equal(t.starts, 2)
end)

test("menu enters Endure, existing Slot 1 and current server before starting loot", function()
    local t = context()
    t.R.MenuEntered = false
    local function node(kind, text, parent)
        local n = {Text = text or "", Name = text or kind, Parent = parent, Visible = true, Enabled = true, children = {}}
        function n:IsA(k) return k == kind or (k == "GuiButton" and kind == "TextButton")
            or (k == "GuiObject" and kind ~= "PlayerGui" and kind ~= "ScreenGui") end
        function n:GetChildren() return self.children end
        function n:GetDescendants()
            local out = {}
            for _, child in ipairs(self.children) do
                out[#out + 1] = child
                for _, desc in ipairs(child:GetDescendants()) do out[#out + 1] = desc end
            end
            return out
        end
        function n:IsDescendantOf(ancestor)
            local p = self.Parent
            while p do if p == ancestor then return true end p = p.Parent end
            return false
        end
        function n:GetFullName() return self.Name end
        n.MouseButton1Click, n.Activated, n.MouseButton1Down = {}, {}, {}
        if parent then parent.children[#parent.children + 1] = n end
        return n
    end
    local pg = node("PlayerGui")
    local screen = node("ScreenGui", nil, pg)
    local play = node("TextButton", "Endure", screen)
    local slots = node("Frame", nil, screen); slots.Visible = false
    local one = node("Frame", nil, slots)
    node("TextLabel", "Slot 1", one)
    local enter = node("TextButton", "Endure", one)
    local delete = node("TextButton", "Deletar", one)
    local two = node("Frame", nil, slots)
    node("TextLabel", "Slot 2", two); node("TextButton", "Endure", two)
    local current = node("TextButton", "Noble Dorman (Current Server)", screen); current.Visible = false
    t.player.FindFirstChild = function(_, name) if name == "PlayerGui" then return pg end end
    local clicks = 0
    getconnections = function() return {true} end
    firesignal = function(event)
        clicks = clicks + 1
        if event == play.MouseButton1Click then play.Visible = false slots.Visible = true
        elseif event == enter.MouseButton1Click then slots.Visible = false current.Visible = true
        elseif event == current.MouseButton1Click then screen.Enabled = false
        else error("clicked an unrelated button") end
    end
    t.R.Bootstrap(); t.advance(1); equal(t.starts, 0)
    t.advance(2); equal(t.starts, 0)
    t.advance(5); equal(clicks, 3); equal(t.starts, 1); assert(t.R.MenuEntered)
    screen.Enabled = true; play.Visible = true
    t.advance(0.5); equal(t.H.State.Running, false)
    equal(t.R.MenuEntered, false)
    getconnections, firesignal = nil, nil
end)

test("death stops farm and sales; a new living character waits five seconds", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1); equal(t.starts, 1)
    t.H.Config.AutoSell = true
    t.H.Sell.Runtime.SellerTrip = {Origin = "old character"}
    t.humanoid.Health = 0
    t.H.Farm.Step()
    equal(t.H.State.Running, false); equal(t.H.Config.AutoSell, false)
    equal(t.H.Sell.Runtime.SellerTrip, nil)
    t.H.Farm.Start(); t.H.Sell.Start(); equal(t.starts, 1)
    t.advance(5); equal(t.starts, 1)
    t.player.Character = {}; t.humanoid = {Health = 100}
    t.H.Farm.Step(); t.advance(4.9); equal(t.starts, 1)
    t.advance(1); equal(t.starts, 2)
    t.player.Character = {} -- Replacement is also guarded even without a sampled death.
    t.H.Farm.Step(); equal(t.H.State.Running, false)
end)

test("actual Work entrypoint deduplicates concurrent and repeated execution and recovers from load failure", function()
    local t = context()
    local compileWork, order, builds, bootstraps = assert(load(workSource)), {}, 0, 0
    t.loaded = false
    appendfile, writefile, isfile = function() end, function() end, function() return true end
    getfenv, setfenv = function() return _G end, function() end
    game.HttpGet = function(_, url) return url:find("server_cycle.lua", 1, true) and "CYCLE" or "BASE" end
    local failExtension = false
    loadstring = function(source, chunk)
        if source == "BASE" then return function()
            builds = builds + 1
            t.H.JobId = tostring(game.JobId); t.H.State.Ready = false; t.H.State.Unloaded = false
            t.env.ENDHUB = t.H
            return t.H
        end end
        return function() return function(H)
            order[#order + 1] = chunk
            if failExtension then error("test extension failure") end
            if source == "CYCLE" then
                H.ServerCycle = {Bootstrap = function() assert(H.State.Ready) bootstraps = bootstraps + 1 end}
            end
        end end
    end
    task.spawn(compileWork); t.advance(0)
    compileWork(); equal(builds, 0)
    t.loaded = true; t.advance(1)
    equal(builds, 1); equal(bootstraps, 1); equal(order[#order], "EndHub server cycle")
    equal(compileWork(), t.H); equal(builds, 1); equal(bootstraps, 1)
    t.env.ENDHUB = nil; failExtension = true
    local ok = pcall(compileWork)
    equal(ok, false); equal(t.env.ENDHUB_BOOT, nil); equal(t.env.ENDHUB_WORK_LOADING, nil)
    equal(t.env.ENDHUB, nil); assert(t.H.State.Unloaded)
    failExtension = false; compileWork(); equal(bootstraps, 2)
end)

test("direct EndHub entrypoint integrates the cycle, while Work defers it until after extensions", function()
    local t = context()
    local cycleLoads, starts = 0, 0
    game.HttpGet = function(_, url) return url end
    loadstring = function(source) return function() return function(H)
        if source:find("modules/server_cycle.lua", 1, true) then
            cycleLoads = cycleLoads + 1
            H.ServerCycle = {Bootstrap = function() assert(H.State.Ready) starts = starts + 1 end}
        end
    end end end
    local direct = assert(load(baseSource))()
    equal(cycleLoads, 1); equal(starts, 1); assert(direct.State.Ready)
    t.env.ENDHUB = nil; t.env.ENDHUB_WORK_LOADING = true
    local deferred = assert(load(baseSource))()
    equal(cycleLoads, 1); equal(starts, 1); equal(deferred.State.Ready, false)
end)

for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    assert(ok, entry[1] .. "\n" .. tostring(err))
    output("PASS " .. entry[1])
end
output(tostring(#tests) .. " server cycle tests passed (simulated services)")
