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
local routeSource = read("modules/trinket_route.lua")
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
    local emptyGui = {GetDescendants = function() return {} end, FindFirstChild = function() end}
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
        equal(t.starts, 0); equal(#t.teleports, 0); assert(t.R.Checks[t.players.list[2]].State == "unknown" or t.R.Checks[t.players.list[2]].State == "pending")
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

test("route points can override the global wait without changing older points", function()
    local t = context({route = true})
    t.loot = false
    t.H.Config.TrinketRoutes[tostring(game.PlaceId)][1][4] = 3
    t.R.Bootstrap(); t.advance(1)
    t.H.Farm.Step(); equal(t.routeTeleports, 1)
    t.advance(1.5); t.H.Farm.Step(); equal(t.routeTeleports, 1)
    t.advance(1.6); t.H.Farm.Step(); equal(t.routeTeleports, 2)
    -- Point 2 has no fourth field and therefore still uses the 1s global wait.
    t.advance(1.1); t.H.Farm.Step(); equal(t.routeTeleports, 2)
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
        function n:IsA(k) return k == kind or (k == "GuiButton" and (kind == "TextButton" or kind == "ImageButton"))
            or (k == "GuiObject" and kind ~= "PlayerGui" and kind ~= "ScreenGui") end
        function n:GetChildren() return self.children end
        function n:FindFirstChild(name)
            for _, child in ipairs(self.children) do if child.Name == name then return child end end
        end
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
    local titleFrame = node("Frame", nil, one)
    local slotTitle = node("TextLabel", "Slot 1", titleFrame)
    slotTitle.AbsolutePosition, slotTitle.AbsoluteSize = {X = 100, Y = 100}, {X = 200, Y = 20}
    local enter = node("TextButton", "Endure", one)
    enter.AbsolutePosition, enter.AbsoluteSize = {X = 100, Y = 400}, {X = 200, Y = 30}
    local delete = node("TextButton", "Deletar", one)
    local two = node("Frame", nil, slots)
    node("TextLabel", "Slot 2", two); node("TextButton", "Endure", two)
    screen.Name = "ServerMenuGui"
    local outer = node("Frame", nil, screen); outer.Name = "Frame"
    local main = node("Frame", nil, outer); main.Name = "MainFrame"
    local list = node("ScrollingFrame", nil, main); list.Name = "ScrollingFrame"
    local current = node("ImageButton", nil, list); current.Name = "ServerMenuTemplate"; current.Visible = false
    local rowFrame = node("Frame", nil, current); rowFrame.Name = "Frame"
    local caption = node("TextLabel", "Noble Dorman (Current Server)", rowFrame); caption.Name = "ServerName"
    current.AbsolutePosition, current.AbsoluteSize = {X = 500, Y = 400}, {X = 300, Y = 30}
    local oldGetService = game.GetService
    game.GetService = function(self, name)
        if name == "GuiService" then return {GetGuiInset = function() return {X = 0, Y = 36} end} end
        if name == "VirtualInputManager" then return {SendMouseButtonEvent = function()
            error("server selection must never use screen coordinates")
        end} end
        return oldGetService(self, name)
    end
    t.player.FindFirstChild = function(_, name) if name == "PlayerGui" then return pg end end
    local clicks = 0
    getconnections = function() return {true} end
    firesignal = function(event)
        clicks = clicks + 1
        if event == play.MouseButton1Click then play.Visible = false slots.Visible = true
        elseif event == enter.MouseButton1Click then slots.Visible = false current.Visible = true
        elseif event == current.Activated then screen.Enabled = false
        else error("clicked an unrelated button") end
    end
    t.R.Bootstrap(); t.advance(1); equal(t.starts, 0)
    t.advance(2); equal(t.starts, 0)
    t.advance(5); equal(clicks, 3); equal(t.starts, 1); assert(t.R.MenuEntered)
    screen.Enabled = true; play.Visible = true
    t.advance(0.5); equal(t.H.State.Running, false)
    equal(t.R.MenuEntered, false)
    play.Visible, slots.Visible, current.Visible = false, false, true
    local sent = 0
    firesignal = function() sent = sent + 1 end
    t.R.ServerEventsTried = {}
    t.advance(15)
    equal(sent, 3); assert(t.R.ServerEventsExhausted)
    equal(t.H.State.Running, false)
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

test("actual Work loader deduplicates callers, patches before bootstrap, and cleans failed loads", function()
    local t = context()
    local compileWork, builds, bootstraps, downloads = assert(load(workSource)), 0, 0, {}
    t.loaded = false
    game.HttpGet = function(_, url) downloads[#downloads + 1] = url return url end
    local failPatch = false
    loadstring = function(source)
        if source:find("EndHub.lua", 1, true) then return function()
            builds = builds + 1
            t.H.JobId = tostring(game.JobId); t.H.State.Ready = false; t.H.State.Unloaded = false
            t.env.ENDHUB = t.H
            return t.H
        end end
        return function() return function(H)
            if failPatch then error("test patch failure") end
            if source:find("server_cycle.lua", 1, true) then
                H.ServerCycle = {MenuStep = function() end, Bootstrap = function()
                    assert(H.State.Ready and downloads[#downloads]:find("server_hop_quality_patch.lua", 1, true))
                    bootstraps = bootstraps + 1
                end}
            end
        end end
    end
    local second
    task.spawn(compileWork); t.advance(0)
    task.spawn(function() second = compileWork() end); t.advance(0.2); equal(builds, 0)
    t.loaded = true; t.advance(1)
    equal(builds, 1); equal(bootstraps, 1); equal(second, t.H)
    equal(compileWork(), t.H); equal(builds, 1)
    t.env.ENDHUB = nil; failPatch = true
    local ok = pcall(compileWork)
    equal(ok, false); equal(t.env.ENDHUB_BOOT, nil); equal(t.env.ENDHUB_WORK_LOADING, nil)
    equal(t.env.ENDHUB, nil); assert(t.H.State.Unloaded)
    failPatch = false; compileWork(); equal(bootstraps, 2)
    t.H.ServerCycle = nil
    compileWork(); equal(bootstraps, 3)
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

test("shared executor files isolate accounts, profiles and visits; legacy settings migrate read-only", function()
    local t = context()
    local files, folders, writes = {}, {}, {}
    local function copy(v) if type(v) ~= "table" then return v end local o = {} for k,x in pairs(v) do o[k] = copy(x) end return o end
    local encoded, sequence = {}, 0
    local http = {JSONEncode = function(_, value) sequence = sequence + 1 local raw = "json" .. sequence encoded[raw] = copy(value) return raw end,
        JSONDecode = function(_, raw) return copy(assert(encoded[raw])) end}
    files["EndHub/config.json"] = http:JSONEncode({PickupDistance = 11, TrinketRoutes = {map = {{1,2,3}}}})
    readfile = function(path) return files[path] end
    writefile = function(path, raw) files[path] = raw writes[#writes+1] = path end
    isfile = function(path) return files[path] ~= nil end
    isfolder = function(path) return folders[path] == true end
    makefolder = function(path) folders[path] = true end
    local function client(id, profile)
        local env = {ENDHUB_PROFILE = profile}
        getgenv = function() return env end
        local player = {UserId = id, FindFirstChild = function() end}
        local services = {Players = {LocalPlayer = player}, HttpService = http,
            UserInputService = {WindowFocused = signal(), WindowFocusReleased = signal()}}
        game.GetService = function(_, name) return services[name] or {} end
        local H = {Config = {}, State = {}, Connections = {}}
        assert(load(read("modules/core.lua")))()(H)
        H.S.Player = player
        assert(load(read("modules/persistence.lua")))()(H)
        return H
    end
    local a, b = client(101), client(202)
    assert(a.Persistence.Dir ~= b.Persistence.Dir)
    equal(a.Config.PickupDistance, 11); equal(b.Config.PickupDistance, 11)
    a.Config.PickupDistance = 4; b.Config.PickupDistance = 9
    a.PersistenceManager.SaveConfig(true); b.PersistenceManager.SaveConfig(true)
    equal(a.Core.ReadJson(a.Persistence.ConfigFile).PickupDistance, 4)
    equal(b.Core.ReadJson(b.Persistence.ConfigFile).PickupDistance, 9)
    a.Core.WriteJson(a.Persistence.VisitedFile, {alpha = 123})
    equal(b.Core.ReadJson(b.Persistence.VisitedFile), nil)
    local again = client(101); equal(again.Config.PickupDistance, 4)
    local other = client(101, "second"); assert(other.Persistence.Dir ~= a.Persistence.Dir)
    for _, path in ipairs(writes) do assert(path:find("EndHub/accounts/",1,true) == 1, path) end
    equal(http:JSONDecode(files["EndHub/config.json"]).PickupDistance, 11)
    -- Executors that cannot make nested folders use a verified flat, isolated file.
    isfolder = function() return false end
    makefolder = function() error("folders unsupported") end
    writefile = function(path, raw)
        if path:find("/", 1, true) then error("nested paths unsupported") end
        files[path] = raw
    end
    typeof = function(value)
        if type(value) == "table" and value.X and value.Y and value.Z then return "Vector3" end
        return type(value)
    end
    local flat = client(404)
    flat.Config.PickupDistance = 6
    assert(flat.PersistenceManager.SaveAll(true))
    assert(not tostring(flat.State.PersistencePath):find("/", 1, true))
    local flatAgain = client(404)
    equal(flatAgain.Config.PickupDistance, 6)
    -- Missing file APIs cannot abort initialization.
    readfile, writefile, isfile, makefolder, isfolder = nil, nil, nil, nil, nil
    client(303)
end)

test("core input never uses OS keys; unfocused clients do not send fallback keys", function()
    local t = context()
    local pressed, released = 0, 0
    keypress, keyrelease = function() error("OS input forbidden") end, function() error("OS input forbidden") end
    local focused = false
    isrbxactive = function() return focused end
    local services = {Players = {LocalPlayer = {UserId = 99}}, UserInputService = {},
        VirtualInputManager = {SendKeyEvent = function(_, down) if down then pressed = pressed + 1 else released = released + 1 end end}}
    game.GetService = function(_, name) return services[name] or {} end
    Enum.KeyCode = {E = "E", One = "One"}
    local H = {State = {}, Config = {}, Connections = {}}
    assert(load(read("modules/core.lua")))()(H)
    equal(H.Core.PressKey(0x45), false); t.advance(1); equal(pressed, 0)
    focused = true; H.Core.PressKey(0x45); H.Core.PressKey(0x45)
    t.advance(0.01); focused = false; t.advance(1)
    equal(pressed, 1); equal(released, 1)
    keypress, keyrelease, isrbxactive = nil, nil, nil
end)

test("role API outage retries automatically without ever authorizing unknown players", function()
    local t = context()
    t.roles[t.player.UserId] = {fail = true}
    t.R.Bootstrap(); t.advance(10)
    equal(t.H.State.Running, false)
    t.roles[t.player.UserId] = {guest = true}
    t.advance(50)
    equal(t.H.State.Running, true)
end)

test("Extras are lazy, repeated open reuses one context, closing cancels a pending download", function()
    local t = context()
    local downloads, opened, closed, shown = 0, 0, 0, 0
    game.HttpGet = function() downloads = downloads + 1 task.wait(1) return "extras" end
    loadstring = function() return function() return function()
        opened = opened + 1
        local ctx = {State = {}, UI = {Library = {Toggle = function() shown = shown + 1 end}}}
        function ctx.CloseExtras() closed = closed + 1 ctx.State.Unloaded = true end
        return ctx
    end end end
    assert(load(read("modules/extras.lua")))()(t.H)
    equal(downloads, 0)
    t.H.Extras.Open(); t.H.Extras.Open(); t.advance(2)
    equal(downloads, 1); equal(opened, 1)
    t.H.Extras.Open(); equal(shown, 1); equal(downloads, 1)
    t.H.Extras.Close(); equal(closed, 1)
    t.H.Extras.Open(); t.advance(0.2); t.H.Extras.Close(); t.advance(2)
    equal(opened, 1); equal(t.H.Extras.Context, nil)
end)

test("compact UI preserves saved sell filters despite dropdown initialization callbacks", function()
    local t = context()
    local library = {Options = {}, Toggles = {}}
    local group = {}
    local function widget(id, spec, toggle)
        local obj = {Value = spec.Default}
        function obj:SetValue(v) self.Value = v if spec.Callback then spec.Callback(v) end end
        function obj:SetValues(v) self.Values = v end
        function obj:SetText(v) self.Text = v end
        (toggle and library.Toggles or library.Options)[id] = obj
        return obj
    end
    function group:AddButton() end
    function group:AddDivider() end
    function group:AddLabel(id) return widget(id, {}) end
    function group:AddToggle(id, spec) return widget(id, spec, true) end
    function group:AddSlider(id, spec) return widget(id, spec) end
    function group:AddDropdown(id, spec)
        local obj = widget(id, spec)
        if spec.Multi and spec.Callback then spec.Callback({}) end
        return obj
    end
    local names = {}
    local tab = {AddLeftGroupbox = function() return group end, AddRightGroupbox = function() return group end}
    function library:CreateWindow() return {AddTab = function(_, name) names[#names+1] = name return tab end} end
    game.HttpGet = function() return string.rep("x", 1001) end
    loadstring = function() return function() return library end end
    Enum.KeyCode = {RightShift = "RightShift"}
    UDim2 = {fromOffset = function() end}
    t.H.Persistence = {Dir = "account"}
    t.H.SellCategories = {"Trinket", "Weapon"}
    local filters = {Common = {Trinket = true}}
    t.H.Sell.GetFilter = function(r, c) return filters[r] and filters[r][c] end
    t.H.Sell.SetFilter = function(r, c, v) filters[r] = filters[r] or {} filters[r][c] = v end
    assert(load(read("modules/ui.lua")))()(t.H)
    equal(#names, 3); equal(names[1], "Farm"); equal(names[3], "Settings")
    equal(filters.Common.Trinket, true)
    equal(t.H.UI.Tabs.Visuals, nil); equal(t.H.UI.Tabs.Movement, nil)
end)

test("pickup timeout, stop and changed filter can clear a pending remote target", function()
    local t = context()
    local H = t.H
    H.S.Player.CharacterAdded = signal()
    H.Farm.ClearTarget = function() H.State.CurrentTarget = nil end
    H.Farm.SkipTarget = function() H.Farm.ClearTarget() end
    H.Farm.Ignore = function() end
    H.Farm.TryBackgroundPickup = function() return true end
    H.Core.DropsFolder = function() return {} end
    assert(load(read("modules/fps_patch.lua")))()(H)
    local drop = {Parent = {}, IsDescendantOf = function() return true end}
    H.State.CurrentTarget, H.State.Running = drop, true
    assert(H.Farm.TryBackgroundPickup(drop))
    H.Farm.ClearTarget(); equal(H.State.CurrentTarget, nil)
    H.Farm.Step(1); equal(H.State.CurrentTarget, nil)
    H.State.CurrentTarget = drop; H.Farm.TryBackgroundPickup(drop)
    H.State.Running = false; H.Farm.ClearTarget(); H.Farm.Step(1)
    equal(H.State.CurrentTarget, nil)
end)

local extrasFile = io.open("../endhub-extras/loader.lua", "r")
if extrasFile then
    local extrasSource = extrasFile:read("*a"); extrasFile:close()
    table.clear = function(t) for k in pairs(t) do t[k] = nil end end
    test("actual Extras context disconnects its own tools, preserves the main controller and rolls back failure", function()
        local t = context()
        local mainLibrary = {}
        t.H.UI = {Library = mainLibrary}
        local mainConnections = #t.H.Connections
        local extraSignal, unloads, failAt = signal(), 0, nil
        game.HttpGet = function(_, url) return assert(url:match("/modules/(.+)%.lua")) end
        local feature = {movement = "Movement", boss = "Boss", players = "PlayerTools", visuals = "Visuals",
            no_killbrick = "NoKillbrick", legacy_features = "Legacy", mob_farm = "MobFarm"}
        loadstring = function(name) return function() return function(ctx)
            ctx.Core.Connect(extraSignal, function() end)
            if name == "ui" then ctx.UI = {Library = {Unload = function() unloads = unloads + 1 end}} end
            if feature[name] then ctx[feature[name]] = {Reset = function() end, Stop = function() end} end
            if name == failAt then error("download/init failure") end
        end end end
        local init = assert(load(extrasSource))()
        local ctx = init(t.H, "https://test/extras")
        assert(t.H.Boss == ctx.Boss and #ctx.Connections > 0)
        equal(#t.H.Connections, mainConnections)
        ctx.State.Status = "shared status"; equal(t.H.State.Status, "shared status")
        ctx.CloseExtras(); ctx.CloseExtras()
        equal(unloads, 1); equal(t.H.State.Unloaded, false); equal(t.H.Boss, nil)
        equal(t.H.UI.Library, mainLibrary)
        for _, c in ipairs(extraSignal.connections) do equal(c.Connected, false) end
        failAt = "boss_ui"
        equal(pcall(init, t.H, "https://test/extras"), false)
        equal(unloads, 2); equal(t.H.State.Unloaded, false)
        for _, c in ipairs(extraSignal.connections) do equal(c.Connected, false) end
    end)
end

test("teleport queue rejects another account and the source job", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    local queued = assert(load(t.queued[1]))
    local boots = 0
    game.HttpGet = function() boots = boots + 1 return "loader" end
    loadstring = function() return function() end end
    queued(); equal(boots, 0)
    game.JobId = "destination"
    t.player.UserId = 999
    queued(); equal(boots, 0)
    t.player.UserId = 1
    queued(); equal(boots, 1)
end)

test("another player's teleport leaves this client's active target and cycle intact", function()
    local t = context()
    local other = t:add(2)
    t.R.Bootstrap(); t.advance(1)
    local drop = {Name = "Goblet"}
    t.H.State.CurrentTarget = drop
    other.OnTeleport:Fire(Enum.TeleportState.Started)
    t.service.TeleportInitFailed:Fire(other, "Failure", "other client", game.PlaceId)
    t.advance(1)
    equal(t.R.Hopping, false); equal(t.H.State.Running, true)
    equal(t.H.State.CurrentTarget, drop)
end)

test("external teleport timeout recovers automatically after fresh checks", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    t.player.OnTeleport:Fire(Enum.TeleportState.Started); t.advance(1)
    equal(t.H.State.Running, false)
    t.advance(31); assert(t.R.Failed); equal(t.H.State.Running, false)
    t.advance(31); equal(t.R.Failed, false); equal(t.H.State.Running, true)
    assert(t.queries[1] >= 2)
end)

test("a transient controller exception pauses safely and does not kill its loop", function()
    local t = context()
    t.R.Bootstrap(); t.advance(1)
    local original = t.R.MenuStep
    local calls = 0
    t.R.MenuStep = function()
        calls = calls + 1
        if calls == 1 then error("transient GUI failure") end
        return original()
    end
    t.advance(0.5); equal(t.H.State.Running, false)
    assert(t.R.LastControllerError:find("transient GUI failure", 1, true))
    t.advance(1); equal(t.H.State.Running, true)
end)

test("quality hop preserves HTTP failure instead of reporting unavailable slots", function()
    local t = context()
    assert(load(read("modules/server_hop_quality_patch.lua")))()(t.H)
    t.R.Bootstrap(); t.advance(1)
    t.httpFails = true
    t.R.RequestHop("test"); t.advance(20)
    equal(#t.teleports, 0); assert(t.R.Failed)
    assert(t.R.Status:find("SERVER LIST REQUEST FAILED", 1, true), t.R.Status)
    assert(not t.R.Status:find("NO SERVER WITH SPACE", 1, true))
end)

test("quality hop retains earlier candidates when a later page fails", function()
    local t = context()
    assert(load(read("modules/server_hop_quality_patch.lua")))()(t.H)
    local calls = 0
    t.serverResponse = function()
        calls = calls + 1
        if calls == 2 then error("HTTP 429 Too Many Requests") end
        return {data = {{id = "eligible", playing = 1, maxPlayers = 20, ping = 200}}, nextPageCursor = "next"}
    end
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(1)
    equal(calls, 2); equal(t.teleports[1], "eligible")
end)

test("quality hop distinguishes a valid empty list, malformed response and page limit", function()
    for _, case in ipairs({
        {response = {data = {}}, message = "SERVER LIST OK BUT NO OTHER SERVER WITH SPACE"},
        {response = {errors = {}}, message = "SERVER LIST INVALID RESPONSE"},
        {response = {data = {}, nextPageCursor = "next"}, message = "SEARCH LIMIT"},
    }) do
        local t = context()
        assert(load(read("modules/server_hop_quality_patch.lua")))()(t.H)
        t.serverResponse = function() return case.response end
        t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(20)
        equal(#t.teleports, 0); assert(t.R.Status:find(case.message, 1, true), t.R.Status)
    end
end)

test("quality hop backs off on 429 and stops pagination after an acceptable candidate", function()
    local t = context()
    assert(load(read("modules/server_hop_quality_patch.lua")))()(t.H)
    local calls = 0
    t.serverResponse = function() calls = calls + 1 error("HTTP 429 Too Many Requests") end
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(20)
    equal(calls, 1); equal(#t.teleports, 0)
    t.R.Stop()
    t = context()
    assert(load(read("modules/server_hop_quality_patch.lua")))()(t.H)
    calls = 0
    t.serverResponse = function()
        calls = calls + 1
        return {data = {{id = "healthy", playing = 1, maxPlayers = 20, ping = 60}}, nextPageCursor = "next"}
    end
    t.R.Bootstrap(); t.advance(1); t.R.RequestHop("test"); t.advance(1)
    equal(calls, 1); equal(t.teleports[1], "healthy")
end)

for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    assert(ok, entry[1] .. "\n" .. tostring(err))
    output("PASS " .. entry[1])
end
output(tostring(#tests) .. " server cycle tests passed (simulated services)")
