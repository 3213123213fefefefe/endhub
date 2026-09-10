return function(H)
    if H.ServerCycle then return H.ServerCycle end
    local ENV, C, cfg = getgenv(), H.Core, H.Config
    local Players, Player = H.S.Players, H.S.Player
    local Groups = game:GetService("GroupService")
    local Teleports = game:GetService("TeleportService")
    local Http = H.S.HttpService
    local GROUP_ID, TESTER_RANK = 36025827, 252
    local SETTING = "EndHubServerCycleV1"
    local JOB, PLACE = tostring(game.JobId), game.PlaceId
    local loaderURL = H.Repo .. "loader.lua"
    local R = {
        Enabled = false, Allowed = false, Checking = false, Hopping = false,
        Closed = false, Generation = 0, Checks = {}, Workers = 0,
        Status = "STOPPED", IdleSince = nil, StartedAt = 0,
    }
    H.ServerCycle = R
    cfg.ServerCycleEnabled = true -- Always start on a fresh load, regardless of saved OFF state.
    cfg.ServerCycleAutoSell = true
    cfg.ServerCycleIdleSeconds = math.max(10, tonumber(cfg.ServerCycleIdleSeconds) or 30)
    cfg.ServerCycleMaxSeconds = math.max(0, tonumber(cfg.ServerCycleMaxSeconds) or 0)
    cfg.ReturnToLootAfterDeath = cfg.ReturnToLootAfterDeath ~= false

    local function status(value)
        if R.Status ~= value then print("[EndHub Cycle] " .. value) end
        R.Status, H.State.ServerCycleStatus = value, value
    end
    local function alive(generation)
        return not R.Closed and not H.State.Unloaded and R.Enabled
            and (not generation or generation == R.Generation)
    end
    local function persist()
        if H.PersistenceManager and H.PersistenceManager.SaveConfig then
            pcall(H.PersistenceManager.SaveConfig, true)
        end
    end
    local function stopWork(preserveTrip)
        if preserveTrip and R.Allowed then
            local runtime = H.Sell and H.Sell.Runtime
            R.PausedWork = {Phase = H.State.FarmSellPhase, Trip = runtime and runtime.SellerTrip}
        elseif not preserveTrip then
            R.PausedWork = nil
        end
        R.Allowed = false
        cfg.AutoFarmSell = false
        if H.Sell then H.Sell.Stop() end
        if H.Farm then H.Farm.Stop() end
    end
    local function intent(enabled)
        pcall(function()
            Teleports:SetTeleportSetting(SETTING, {Enabled = enabled, PlaceId = PLACE})
        end)
    end
    -- Bounded waiting also handles a group/HTTP request that never returns.
    -- A late result has no side effects and cannot restart an old generation.
    local function bounded(fn, seconds, generation)
        local done, ok, result = false, false, nil
        task.spawn(function()
            ok, result = pcall(fn)
            done = true
        end)
        local untilTime = tick() + seconds
        while not done and alive(generation) and tick() < untilTime do task.wait(0.1) end
        if not alive(generation) then return false, "cancelled" end
        if not done then return false, "request timeout" end
        return ok, result
    end
    local function normalized(name)
        return tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    end
    -- Ranks confirmed from groups.roblox.com/v1/groups/36025827/roles.
    -- Prefer fresh group metadata, but retain the verified threshold on failure.
    local blockedNames = {tester = true, ["money tester"] = true, admin = true, owner = true}
    function R.IsRelevantRole(name, rank)
        name = normalized(name)
        if name == "member" or name == "guest" then return false end
        return blockedNames[name] == true or (tonumber(rank) or 0) >= TESTER_RANK
    end
    local function readRoles(player)
        local ok, result = pcall(function() return Groups:GetRolesInGroupAsync(player.UserId, GROUP_ID) end)
        if ok and type(result) == "table" then
            if result.IsMember == false then return {{Name = "Guest", Rank = 0}} end
            if result.IsMember == true and type(result.Roles) == "table" and #result.Roles > 0 then
                local valid = true
                for _, role in ipairs(result.Roles) do
                    if type(role.Name) ~= "string" or type(role.Rank) ~= "number" then valid = false break end
                end
                if valid then return result.Roles end
            end
        end
        -- Compatibility for clients where the multiple-role API is unavailable.
        local groups = Groups:GetGroupsAsync(player.UserId)
        if type(groups) ~= "table" then error("invalid group response") end
        for _, group in ipairs(groups) do
            if group.Id == GROUP_ID then
                if type(group.Role) ~= "string" or type(group.Rank) ~= "number" then
                    error("group response has no role/rank")
                end
                return {{Name = group.Role, Rank = group.Rank}}
            end
        end
        return {{Name = "Guest", Rank = 0}}
    end

    local queueFunction = queue_on_teleport or queueonteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
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
-- Some executors may deliver their teleport queue to another client. Do not
-- initialize there, or rerun this queue in the source job before teleport.
local expectedUser, sourceJob = %s, %q
local players = game:GetService("Players")
while not game:IsLoaded() or not players.LocalPlayer do task.wait(0.1) end
if players.LocalPlayer.UserId ~= expectedUser or tostring(game.JobId) == sourceJob then return end
local ok, data = pcall(function()
    return game:GetService("TeleportService"):GetTeleportSetting(%q)
end)
-- Loading again always starts a fresh cycle, even if the previous session was stopped.
local source = game:HttpGet(%q .. "?v=" .. tostring(os.time()))
local fn, err = loadstring(source)
assert(fn, err)
fn()
]=], tostring(Player.UserId), JOB, SETTING, loaderURL)
        local ok, err = pcall(queueFunction, code)
        if not ok then
            R.Continuity = "AUTOEXEC REQUIRED"
            warn("[EndHub Cycle] teleport queue failed: " .. tostring(err))
            return false
        end
        ENV.ENDHUB_QUEUED_JOB = JOB
        R.Continuity = "TELEPORT QUEUED"
        return true
    end

    local visitedFile = H.Persistence and H.Persistence.VisitedFile or "EndHub/serverhop_visited.json"
    local visits = C.ReadJson(visitedFile) or {}
    local function pruneVisits()
        for key, time in pairs(visits) do
            if type(time) ~= "number" or os.time() - time > 3600 then visits[key] = nil end
        end
    end
    local function visit(id)
        pruneVisits()
        visits[tostring(PLACE) .. ":" .. id] = os.time()
        C.WriteJson(visitedFile, visits)
    end
    local function chooseServer(generation)
        local cursor = nil
        pruneVisits()
        for _ = 1, 6 do
            if not alive(generation) then return nil end
            local url = "https://games.roblox.com/v1/games/" .. tostring(PLACE)
                .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
            if cursor then url = url .. "&cursor=" .. Http:UrlEncode(cursor) end
            local ok, data = bounded(function() return Http:JSONDecode(game:HttpGet(url)) end, 12, generation)
            if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
                return nil, "SERVER LIST UNAVAILABLE"
            end
            for _, server in ipairs(data.data) do
                if type(server.id) == "string" and server.id ~= JOB
                    and type(server.playing) == "number" and type(server.maxPlayers) == "number"
                    and server.playing < server.maxPlayers
                    and not visits[tostring(PLACE) .. ":" .. server.id] then
                    return server.id
                end
            end
            cursor = data.nextPageCursor
            if type(cursor) ~= "string" or cursor == "" then break end
        end
        return nil, "NO UNVISITED SERVER WITH SPACE"
    end
    function R.RequestHop(reason)
        if not alive() or R.Hopping then return false end
        R.Hopping = true -- Acquire before the first yielding operation.
        R.HopOwned = true
        R.DeathReturn, R.LastLootPosition, R.LastLootCharacter = nil, nil, nil
        stopWork()
        local generation = R.Generation
        status("HOP REQUESTED: " .. tostring(reason or "manual"))
        persist()
        R.QueueBootstrap()
        visit(JOB)
        task.spawn(function()
            local lastError = "TELEPORT NOT COMPLETED"
            for attempt = 1, 3 do
                if not alive(generation) then return end
                local server, err = chooseServer(generation)
                if not alive(generation) then return end
                if server then
                    R.HopFailed, R.HopError = false, nil
                    R.TargetServer = server
                    visit(server)
                    status("TELEPORTING " .. server .. " | TRY " .. attempt)
                    local ok, errorMessage = pcall(function()
                        Teleports:TeleportToPlaceInstance(PLACE, server, Player)
                    end)
                    if not ok then R.HopFailed = true lastError = tostring(errorMessage) end
                    local untilTime = tick() + 30
                    while alive(generation) and not R.HopFailed and tick() < untilTime do task.wait(0.25) end
                    -- Successful teleport destroys this VM. A surviving VM
                    -- must retry or report failure rather than assume success.
                    lastError = R.HopError or lastError
                else
                    lastError = err or lastError
                end
                if alive(generation) and attempt < 3 then
                    status("HOP RETRY: " .. lastError)
                    task.wait(attempt * 3)
                end
            end
            if alive(generation) then
                R.Hopping = false
                R.HopOwned = false
                R.Failed = true
                status("HOP PAUSED: " .. lastError .. " | USE RETRY")
            end
        end)
        return true
    end
    -- Public integration point for a future external hop trigger.
    H.ServerHop = H.ServerHop or {}
    if not H.ServerHop.Request then H.ServerHop.Request = R.RequestHop end
    function R.OnLootComplete()
        if R.Enabled and R.Allowed then
            -- Let the existing delayed pickup confirmation finish before judging the lap.
            if tick() - (H.State.LastPickup or -math.huge) < 0.6 then return true end
            -- Count also checks still-visible drops, including temporarily ignored targets.
            if H.Farm.Count then H.Farm.Count() end
            local sawMatching = R.RouteSawMatching
            R.RouteSawMatching = false
            local collected = H.State.LootPickupSerial or 0
            local previous = R.RoutePickupStart or 0
            R.RoutePickupStart = collected
            if collected > previous or sawMatching then
                status("ROUTE COLLECTED/DETECTED MATCHING LOOT | STARTING ANOTHER LAP")
                return false
            end
            return R.RequestHop("FULL ROUTE WITHOUT PICKUP OR MATCHING DETECTION")
        end
        return false
    end

    -- The final Allowed implementation includes the existing name/rarity filters.
    -- Remember detections even if pickup fails or the target is temporarily ignored.
    local oldAllowed = H.Farm.Allowed
    function H.Farm.Allowed(...)
        local allowed = oldAllowed(...)
        if allowed and R.Enabled and R.Allowed then R.RouteSawMatching = true end
        return allowed
    end
    function R.CharacterReady()
        local character, hum = Player.Character, C.Humanoid()
        if not character or not C.Root() or not hum or hum.Health <= 0 then
            R.ReadyCharacter, R.CharacterReadyAt = nil, nil
            R.MenuEntered, R.MenuClearSince = false, nil
            return false
        end
        if character ~= R.ReadyCharacter then
            R.ReadyCharacter = character
            R.CharacterReadyAt = tick() + 5
            R.MenuEntered, R.MenuClearSince = false, nil
        end
        return tick() >= (R.CharacterReadyAt or math.huge)
    end
    function R.PauseForCharacter()
        if not R.CharacterPaused then
            local hum = C.Humanoid()
            local diedWhileLooting = cfg.ReturnToLootAfterDeath
                and R.LastLootPosition and R.LastLootCharacter == Player.Character
                and tick() - (R.LastLootAt or -math.huge) <= 3
                and (not hum or hum.Health <= 0)
            if diedWhileLooting then
                R.DeathReturn = {Position = R.LastLootPosition, Character = R.LastLootCharacter}
                print("[EndHub Death] saved loot return position=" .. tostring(R.LastLootPosition))
            end
            R.CharacterPaused = true
            stopWork()
            status("WAIT PLAY / RESPAWN + 5 SECONDS")
        end
    end
    local oldStart, oldStep = H.Farm.Start, H.Farm.Step
    function H.Farm.Start(...)
        if not R.CharacterReady() then R.PauseForCharacter() return false end
        if not R.MenuEntered then return false end
        if R.Enabled and not R.Allowed then return false end
        return oldStart(...)
    end
    function H.Farm.Step(...)
        local root, hum = C.Root(), C.Humanoid()
        if root and root.Position and hum and hum.Health > 0 and R.Enabled and R.Allowed
            and H.State.Running and H.State.FarmSellPhase == "FARM" and not cfg.AutoSell then
            local p = root.Position
            R.LastLootPosition = Vector3.new(p.X, p.Y, p.Z)
            R.LastLootCharacter = Player.Character
            R.LastLootAt = tick()
        end
        if not R.CharacterReady() then R.PauseForCharacter() return end
        if not R.MenuEntered then return end
        if R.Enabled and not R.Allowed then return end
        return oldStep(...)
    end
    if H.Sell then
        for _, key in ipairs({"Start", "Step", "AutoFarmStep"}) do
            local original = H.Sell[key]
            if original then H.Sell[key] = function(...)
                if not R.CharacterReady() then R.PauseForCharacter() return end
                if not R.MenuEntered then return end
                if R.Enabled and not R.Allowed then return end
                return original(...)
            end end
        end
    end
    -- Menu flow observed in the game: Resistir / Play -> Slot 1 -> Current Server.
    -- Only inspect visible game UI; never select a new/delete/purchase slot button.
    function R.MenuStep()
        local pg = Player:FindFirstChild("PlayerGui")
        if not pg then status("WAIT PLAYER GUI") return true end
        local function visible(obj)
            local node = obj
            while node and node ~= pg do
                if node:IsA("GuiObject") and not node.Visible then return false end
                if node:IsA("ScreenGui") and not node.Enabled then return false end
                node = node.Parent
            end
            return node == pg
        end
        local function label(obj)
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                return normalized(tostring(obj.Text):gsub("<[^>]+>", ""))
            end
            return ""
        end
        local function buttonFor(obj)
            local node = obj
            for _ = 1, 4 do
                if not node or node == pg or node:IsA("ScreenGui") then break end
                if node:IsA("GuiButton") then return node end
                -- Some rows put their caption next to a transparent click button.
                for _, child in ipairs(node:GetChildren()) do
                    if child:IsA("GuiButton") and visible(child)
                        and (label(child) == label(obj) or
                            (node == obj.Parent and label(child) == "" and normalized(child.Name) == "button")) then
                        return child
                    end
                end
                node = node.Parent
            end
        end
        local play, current, slotOne, slotLabel = {}, nil, nil, nil
        local sawMenu, sawSlots = false, false
        -- Exact hierarchy confirmed by the user's live GUI diagnostic.
        local serverGui = pg:FindFirstChild("ServerMenuGui")
        local outer = serverGui and serverGui:FindFirstChild("Frame")
        local main = outer and outer:FindFirstChild("MainFrame")
        local list = main and main:FindFirstChild("ScrollingFrame")
        if list and visible(list) then
            sawMenu = true
            for _, row in ipairs(list:GetChildren()) do
                local frame = row:FindFirstChild("Frame")
                local name = frame and frame:FindFirstChild("ServerName")
                local text = name and label(name) or ""
                if row:IsA("ImageButton") and visible(row)
                    and (text:find("current server", 1, true) or text:find("servidor atual", 1, true)) then
                    current = row
                    break
                end
            end
        end
        for _, obj in ipairs(pg:GetDescendants()) do
            if visible(obj) then
                local text = label(obj)
                if text == "endure" or text == "play" or text == "resist" or text == "resistir" or text == "jogar" then
                    sawMenu = true
                    local button = buttonFor(obj)
                    if button then play[#play + 1] = button end
                elseif text:match("^slot%s*%d+$") then
                    sawMenu, sawSlots = true, true
                    if text:match("^slot%s*1$") then slotOne, slotLabel = obj.Parent, obj end
                elseif text:find("current server", 1, true) or text:find("servidor atual", 1, true) then
                    sawMenu = true
                    current = current or buttonFor(obj) or obj -- Clickable server rows may be Frames/TextLabels.
                elseif text == "menu do servidor" or text == "server menu" or text == "the veil" then
                    sawMenu = true
                end
            end
        end
        if not sawMenu then
            local hum = C.Humanoid()
            if not C.Root() or not hum or hum.Health <= 0 then
                R.MenuClearSince = nil
                status("WAIT CHARACTER AFTER MENU")
                return true
            end
            R.MenuClearSince = R.MenuClearSince or tick()
            if tick() - R.MenuClearSince < 1 then return true end
            R.MenuEntered = true
            print("[EndHub Menu] menu closed and character ready")
            return false
        end
        R.MenuEntered = false
        R.MenuClearSince = nil
        local target = current
        if not target then
            for _, candidate in ipairs(play) do
                if not sawSlots or (slotOne and candidate:IsDescendantOf(slotOne)) then
                    target = candidate
                    break
                end
            end
        end
        if not target and sawSlots and slotLabel then
            -- The Endure button can be a sibling below the card, not a child
            -- of its title. Match the Slot 1 column using live GUI positions.
            local p, size = slotLabel.AbsolutePosition, slotLabel.AbsoluteSize
            if p and size then
                local centerX, best = p.X + size.X / 2, math.huge
                for _, candidate in ipairs(play) do
                    local cp, cs = candidate.AbsolutePosition, candidate.AbsoluteSize
                    if cp and cs and cp.Y >= p.Y + size.Y
                        and centerX >= cp.X and centerX <= cp.X + cs.X then
                        local distance = cp.Y - p.Y
                        if distance < best then target, best = candidate, distance end
                    end
                end
            end
        end
        if not target then status("WAIT MENU BUTTON / SLOT 1 / CURRENT SERVER") return true end
        if target == current and R.ServerEventsExhausted then
            status("SERVER ENTRY PAUSED | USE RETRY CHECK / HOP")
            return true
        end
        if tick() - (R.LastMenuClick or -math.huge) < 2 then return true end
        R.LastMenuClick = tick()
        local retrySameTarget = R.LastMenuTarget == target
        R.LastMenuTarget = target
        local ok, err = pcall(function()
            if target == current then
                assert(target:IsA("GuiButton"), "current server has no resolved ImageButton")
                assert(type(getconnections) == "function" and type(firesignal) == "function",
                    "direct server activation unavailable; coordinate clicks disabled")
                R.ServerEventsTried = R.ServerEventsTried or {}
                local selected, counts = nil, {}
                for _, name in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down"}) do
                    local count = #getconnections(target[name])
                    counts[#counts + 1] = name .. "=" .. count
                    if count > 0 and not R.ServerEventsTried[name] and not selected then selected = name end
                end
                print("[EndHub Menu] server events | " .. table.concat(counts, " | "))
                if not selected then
                    R.ServerEventsExhausted = true
                    error("no untried server event; entry paused, coordinate clicks disabled")
                end
                R.ServerEventsTried[selected] = true
                print("[EndHub Menu] direct server event=" .. selected)
                if selected == "Activated" then firesignal(target.Activated, nil, 1)
                elseif selected == "MouseButton1Down" then
                    local p, size = target.AbsolutePosition, target.AbsoluteSize
                    firesignal(target.MouseButton1Down, p.X + size.X / 2, p.Y + size.Y / 2)
                else firesignal(target.MouseButton1Click) end
                return
            end
            -- Use one connected signal, never all of them (which can enter twice).
            if target ~= current and target:IsA("GuiButton") and not retrySameTarget
                and type(getconnections) == "function" and type(firesignal) == "function" then
                for _, event in ipairs({target.MouseButton1Click, target.Activated, target.MouseButton1Down}) do
                    if #getconnections(event) > 0 then firesignal(event) return end
                end
            end
            if C.InputFocused and not C.InputFocused() then error("waiting for direct GUI activation / window focus") end
            local position, size = target.AbsolutePosition, target.AbsoluteSize
            local x, y = position.X + size.X / 2, position.Y + size.Y / 2
            -- AbsolutePosition already locates this row. Adding the top inset
            -- can move the click into the next server (rows are only 49px tall).
            print("[EndHub Menu] mouse center=" .. x .. "," .. y
                .. " | row=" .. position.X .. "," .. position.Y .. " size=" .. size.X .. "," .. size.Y)
            local input = game:GetService("VirtualInputManager")
            pcall(function() input:SendMouseMoveEvent(x, y, game) end)
            input:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.08)
            input:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        status(ok and "MENU: ENTERING GAME" or "MENU CLICK FAILED")
        print("[EndHub Menu] " .. target:GetFullName() .. " | " .. (ok and "clicked" or tostring(err)))
        return true -- A click is not evidence that the character has entered.
    end
    local function tryResume()
        if not alive() or R.Hopping or R.Failed or R.Checking or R.Allowed then return end
        for _, player in ipairs(Players:GetPlayers()) do
            local record = R.Checks[player]
            if not record or record.State ~= "allowed" then return end
        end
        local characterReady = R.CharacterReady()
        if R.MenuStep() then return end
        if not characterReady then R.PauseForCharacter() return end
        R.CharacterPaused = false
        if not C.Root() then status("WAIT CHARACTER") return end
        if R.DeathReturn then
            local destination = R.DeathReturn.Position
            R.DeathReturn, R.LastLootPosition, R.LastLootCharacter = nil, nil, nil
            C.Noclip(true)
            if C.Teleport(destination) then
                if H.ResumeTrinketRouteAfterDeath then pcall(H.ResumeTrinketRouteAfterDeath) end
                task.spawn(function() pcall(function() Player:RequestStreamAroundAsync(destination, 2) end) end)
                print("[EndHub Death] returned to loot position=" .. tostring(destination))
                status("RETURNED AFTER DEATH | RESUMING LOOT")
            end
        end
        R.Allowed, R.IdleSince = true, nil
        cfg.AutoFarmSell = cfg.ServerCycleAutoSell
        local toggle = H.UI and H.UI.Toggles and H.UI.Toggles.EH_FarmSell
        if toggle and toggle.SetValue then
            R.SyncingUI = true
            pcall(function() toggle:SetValue(cfg.AutoFarmSell) end)
            R.SyncingUI = false
        end
        local paused = R.PausedWork
        R.PausedWork = nil
        if paused and paused.Phase == "SELL" and cfg.ServerCycleAutoSell and H.Sell then
            if H.Sell.Runtime then H.Sell.Runtime.SellerTrip = paused.Trip end
            H.State.FarmSellPhase = "SELL"
            H.Sell.Start()
            status("SELL RESUMED | PLAYERS CHECKED")
            return
        end
        cfg.AutoSell = false
        H.State.FarmSellPhase = "FARM"
        H.Farm.Start()
        status("LOOT RUNNING | PLAYERS CHECKED")
    end
    local function enqueue(player)
        if not alive() or R.Hopping or R.Checks[player] then return end
        local generation = R.Generation
        local record = {State = "pending", UserId = player.UserId}
        R.Checks[player] = record
        stopWork(true) -- New arrivals pause before the query; keep a sale's return position.
        status("CHECKING PLAYER " .. tostring(player.UserId))
        task.spawn(function()
            while alive(generation) and (R.Checking or R.Workers >= 2) do task.wait(0.1) end
            if not alive(generation) or player.Parent ~= Players then return end
            R.Workers = R.Workers + 1
            local success, roles
            for attempt = 1, 3 do
                success, roles = bounded(function() return readRoles(player) end, 10, generation)
                if success or not alive(generation) or player.Parent ~= Players then break end
                if attempt < 3 then task.wait(attempt) end
            end
            if generation == R.Generation then R.Workers = math.max(0, R.Workers - 1) end
            if not alive(generation) or R.Hopping or player.Parent ~= Players or R.Checks[player] ~= record then return end
            if not success then
                record.State = "unknown"
                record.RetryAt = tick() + 30 + math.random(0, 10)
                status("ROLE CHECK FAILED " .. player.UserId .. " | AUTO RETRY IN 30-40s | " .. tostring(roles))
                return
            end
            record.State = "allowed"
            for _, role in ipairs(roles) do
                print("[EndHub Role] UserId=" .. player.UserId .. " | role=" .. role.Name .. " | rank=" .. role.Rank)
                if R.IsRelevantRole(role.Name, role.Rank) then
                    record.State = "blocked"
                    R.RequestHop("ROLE " .. role.Name .. " | UserId=" .. player.UserId)
                    return
                end
            end
            tryResume()
        end)
    end
    function R.Start()
        if R.Closed or H.State.Unloaded or R.Enabled then return end
        R.Enabled, cfg.ServerCycleEnabled = true, true
        R.Generation = R.Generation + 1
        R.Checks, R.Checking, R.Failed, R.Hopping = {}, true, false, false
        R.Workers, R.HopRetryAt = 0, nil
        R.HopOwned = false
        R.StartedAt = tick()
        R.ServerEventsTried, R.ServerEventsExhausted = {}, false
        stopWork()
        intent(true)
        persist()
        local generation = R.Generation
        status("WAIT GAME / PLAYERS")
        task.spawn(function()
            while alive(generation) and (not game:IsLoaded() or not Players.LocalPlayer or not H.State.Ready) do task.wait(0.1) end
            if not alive(generation) then return end
            -- Refresh the threshold without allowing a failed request to be
            -- interpreted as "there are no relevant roles".
            local ok, info = bounded(function() return Groups:GetGroupInfoAsync(GROUP_ID) end, 5, generation)
            if ok and type(info) == "table" and type(info.Roles) == "table" then
                for _, role in ipairs(info.Roles) do
                    if normalized(role.Name) == "tester" and type(role.Rank) == "number" and role.Rank > 1 then
                        TESTER_RANK = role.Rank
                    end
                end
            end
            if not alive(generation) then return end
            R.QueueBootstrap()
            for _, player in ipairs(Players:GetPlayers()) do enqueue(player) end
            R.Checking = false
            tryResume()
        end)
    end
    function R.Stop()
        if R.Closed then return end
        R.Generation = R.Generation + 1
        stopWork()
        R.Enabled, cfg.ServerCycleEnabled = false, false
        R.Hopping, R.Failed, R.Checking = false, false, false
        R.HopOwned = false
        R.DeathReturn, R.LastLootPosition, R.LastLootCharacter = nil, nil, nil
        intent(false)
        persist()
        status("STOPPED")
    end
    function R.Retry()
        if R.Hopping then return end
        R.Stop()
        R.Start()
    end
    function R.Close()
        if R.Closed then return end
        R.Generation = R.Generation + 1
        stopWork()
        R.Enabled, R.Closed = false, true
        intent(false)
    end
    local oldUnload = H.Unload
    function H:Unload()
        R.Close()
        return oldUnload(self)
    end
    C.Connect(Players.PlayerAdded, function(player)
        if R.Enabled then enqueue(player) end
    end)
    C.Connect(Players.PlayerRemoving, function(player)
        R.Checks[player] = nil
        task.defer(tryResume)
    end)
    local function teleportFailed(message)
        R.HopFailed, R.HopError = true, tostring(message)
        if not R.HopOwned then
            R.Hopping, R.Failed = false, true
            R.HopRetryAt = tick() + 30
            status("TELEPORT FAILED: " .. R.HopError .. " | AUTO RETRY IN 30s")
        end
    end
    C.Connect(Teleports.TeleportInitFailed, function(player, _, message)
        if alive() and player == Player and R.Hopping then teleportFailed(message) end
    end)
    C.Connect(Player.OnTeleport, function(state)
        if not alive() then return end
        R.LastTeleportEvent = tostring(state)
        print("[EndHub Teleport] user=" .. tostring(Player.UserId) .. " | job=" .. JOB
            .. " | event=" .. R.LastTeleportEvent .. " | owned=" .. tostring(R.HopOwned))
        if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
            stopWork()
            local wasHopping = R.Hopping
            R.Hopping = true
            R.QueueBootstrap()
            if not wasHopping then
                local generation = R.Generation
                task.delay(30, function()
                    if alive(generation) and R.Hopping and not R.HopOwned then
                        teleportFailed("teleport did not complete")
                    end
                end)
            end
        elseif state == Enum.TeleportState.Failed then
            teleportFailed("teleport failed")
        end
    end)
    function R.Diagnostic()
        local target = H.State.CurrentTarget
        return "user=" .. tostring(Player.UserId) .. " | job=" .. JOB
            .. " | running=" .. tostring(H.State.Running) .. " | allowed=" .. tostring(R.Allowed)
            .. " | hopping=" .. tostring(R.Hopping) .. " | failed=" .. tostring(R.Failed)
            .. " | cycle=" .. tostring(R.Status) .. " | farm=" .. tostring(H.State.Status)
            .. " | sale=" .. tostring(H.State.SellStatus) .. " | target=" .. (target and target.Name or "none")
            .. " | targetAge=" .. tostring(target and math.floor(tick() - (H.State.TargetStarted or tick())) or 0)
            .. " | lastTeleport=" .. tostring(R.LastTeleportEvent)
            .. " | lastError=" .. tostring(R.LastControllerError)
    end
    task.spawn(function()
        while not R.Closed and not H.State.Unloaded do
            local ok, err = pcall(function()
            R.LastControllerTick = tick()
            if alive() and not R.Hopping then
                for player, record in pairs(R.Checks) do
                    if record.State == "unknown" and record.RetryAt and tick() >= record.RetryAt then
                        R.Checks[player] = nil
                        if player.Parent == Players then enqueue(player) end
                    end
                end
                if R.Failed and R.HopRetryAt and tick() >= R.HopRetryAt then R.Retry() end
                if not R.CharacterReady() then R.PauseForCharacter() end
                if R.Allowed and R.MenuStep() then stopWork(true) end
                tryResume()
                -- Automatic loot hops are decided only at the end of a complete route.
            end
            end)
            if not ok then
                R.LastControllerError = tostring(err)
                R.Allowed = false
                H.State.Running = false
                cfg.AutoSell, cfg.AutoFarmSell = false, false
                pcall(stopWork, true)
                status("CONTROLLER ERROR: " .. R.LastControllerError)
                if not R.ErrorReported then warn("[EndHub Pause] " .. R.Diagnostic()) end
                R.ErrorReported = true
            else R.ErrorReported = false end
            local target = H.State.CurrentTarget
            local age = target and math.max(0, tick() - (H.State.TargetStarted or tick())) or 0
            if alive() and (not H.State.Running or age > (tonumber(cfg.TargetTimeout) or 15) + 5)
                and tick() >= (R.NextPauseLog or 0) then
                R.NextPauseLog = tick() + 15
                print("[EndHub Pause] " .. R.Diagnostic())
            end
            task.wait(0.5)
        end
    end)
    local tabs, options = H.UI and H.UI.Tabs, H.UI and H.UI.Options
    if tabs and tabs.Botting then
        local group = tabs.Botting:AddRightGroupbox("Loot + ServerHop")
        group:AddButton({Text = "START CONTINUOUS CYCLE", Func = R.Start})
        group:AddButton({Text = "STOP CONTINUOUS CYCLE", Func = R.Stop})
        group:AddButton({Text = "RETRY CHECK / HOP", Func = R.Retry})
        group:AddButton({Text = "PRINT PAUSE DIAGNOSTIC", Func = function() print("[EndHub Pause] " .. R.Diagnostic()) end})
        group:AddButton({Text = "SERVERHOP NOW", Func = function() R.RequestHop("manual") end})
        group:AddToggle("EH_CycleAutoSell", {Text = "Sell when full", Default = cfg.ServerCycleAutoSell,
            Callback = function(value) cfg.ServerCycleAutoSell = value if R.Allowed then cfg.AutoFarmSell = value end end})
        group:AddToggle("EH_ReturnToLootAfterDeath", {Text = "Return to loot position after death", Default = cfg.ReturnToLootAfterDeath,
            Callback = function(value) cfg.ReturnToLootAfterDeath = value if not value then R.DeathReturn = nil end end})
        group:AddLabel("EH_CycleStatus", {Text = "Cycle: waiting", DoesWrap = true})
        group:AddLabel("Checks group 36025827 before looting and on new arrivals. Member is ignored. Stop pauses this session. Every fresh load starts automatically. A saved route is required for automatic loot hops.", true)
        task.spawn(function()
            while not R.Closed and not H.State.Unloaded do
                if options and options.EH_CycleStatus then
                    options.EH_CycleStatus:SetText(R.Status .. " | " .. tostring(R.Continuity or "WAITING"))
                end
                task.wait(0.5)
            end
        end)
    end
    function R.Bootstrap()
        cfg.ServerCycleEnabled, cfg.ServerCycleAutoSell = true, true
        R.Start()
    end
    return R
end
