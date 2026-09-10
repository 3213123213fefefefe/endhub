return function(H)
    local F, C, cfg = H.Farm, H.Core, H.Config
    local mapKey = tostring(game.PlaceId)
    cfg.TrinketExplore = cfg.TrinketExplore ~= false
    cfg.TrinketRouteESP = cfg.TrinketRouteESP == true
    cfg.TrinketRoutes = type(cfg.TrinketRoutes) == 'table' and cfg.TrinketRoutes or {}
    cfg.TrinketRoutes[mapKey] = type(cfg.TrinketRoutes[mapKey]) == 'table' and cfg.TrinketRoutes[mapKey] or {}
    cfg.TrinketRouteWait = math.clamp(tonumber(cfg.TrinketRouteWait) or 1, 1, 10)
    cfg.TrinketRouteLootRadius = math.clamp(tonumber(cfg.TrinketRouteLootRadius) or 140, 40, 300)
    local route = cfg.TrinketRoutes[mapKey]
    local index, waitUntil, selected = 0, 0, nil
    local waiting, streaming = false, false
    local markerFolder

    function H.GetTrinketRouteStatus()
        return {Index = index, Total = #route, Remaining = waiting and math.max(0, waitUntil - tick()) or 0}
    end

    local function save()
        if H.PersistenceManager and H.PersistenceManager.SaveConfig then
            local ok, result = pcall(H.PersistenceManager.SaveConfig, true)
            if not ok or result == false then warn('[EndHub Route] could not save route to disk') return false end
            print('[EndHub Route] saved | map=' .. mapKey .. ' | points=' .. #route)
            return true
        end
        warn('[EndHub Route] persistence unavailable')
        return false
    end
    local function reset()
        index, waitUntil, waiting = 0, 0, false
        F.ClearTarget()
    end
    local function labels()
        local values = {}
        for i, p in ipairs(route) do values[#values + 1] = string.format('%d | %.1f, %.1f, %.1f | wait %.0fs', i, p[1], p[2], p[3], tonumber(p[4]) or cfg.TrinketRouteWait) end
        if #values == 0 then values[1] = 'No saved points' end
        return values
    end

    for i = #route, 1, -1 do
        local p = route[i]
        local valid = type(p) == 'table'
        for n = 1, 3 do
            local v = valid and tonumber(p[n])
            if not v or v ~= v or math.abs(v) == math.huge then valid = false break end
            p[n] = v
        end
        if not valid then table.remove(route, i) end
    end

    local group = H.UI.Tabs.Botting:AddLeftGroupbox('Trinket Route')
    group:AddToggle('EH_TrinketExplore', {Text = 'Use saved search points', Default = cfg.TrinketExplore,
        Callback = function(value) cfg.TrinketExplore = value reset() end})
    local function clearMarkers() if markerFolder then markerFolder:Destroy() markerFolder = nil end end
    local function drawMarkers()
        clearMarkers()
        if not cfg.TrinketRouteESP or #route == 0 then return end
        markerFolder = Instance.new('Folder') markerFolder.Name = 'EndHubRoutePoints' markerFolder.Parent = workspace
        local last
        for i, p in ipairs(route) do
            local part = Instance.new('Part')
            part.Name, part.Anchored, part.CanCollide, part.CanQuery, part.Transparency = 'Point_' .. i, true, false, false, 0.25
            part.Shape, part.Size, part.Material = Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), Enum.Material.Neon
            part.Color = i == index and Color3.fromRGB(80,255,100) or Color3.fromRGB(70,160,255)
            part.Position, part.Parent = Vector3.new(p[1], p[2], p[3]), markerFolder
            local gui = Instance.new('BillboardGui') gui.AlwaysOnTop, gui.Size, gui.StudsOffset = true, UDim2.fromOffset(110, 30), Vector3.new(0, 2, 0) gui.Parent = part
            local text = Instance.new('TextLabel') text.BackgroundTransparency, text.Size, text.TextScaled = 1, UDim2.fromScale(1,1), true
            text.Text, text.TextColor3, text.Parent = tostring(i) .. ' (' .. tostring(tonumber(p[4]) or cfg.TrinketRouteWait) .. 's)', Color3.new(1,1,1), gui
            if last then
                local a0, a1, beam = Instance.new('Attachment', last), Instance.new('Attachment', part), Instance.new('Beam')
                beam.Attachment0, beam.Attachment1, beam.Width0, beam.Width1, beam.FaceCamera = a0, a1, .15, .15, true beam.Parent = last
            end
            last = part
        end
    end
    group:AddToggle('EH_TrinketRouteESP', {Text = 'Show numbered route points', Default = cfg.TrinketRouteESP,
        Callback = function(value) cfg.TrinketRouteESP = value drawMarkers() end})
    group:AddSlider('EH_TrinketRouteWait', {Text = 'Wait before looting at each point', Default = cfg.TrinketRouteWait,
        Min = 1, Max = 10, Rounding = 0, Suffix = ' s', Callback = function(value) cfg.TrinketRouteWait = value drawMarkers() end})
    group:AddDropdown('EH_TrinketRoutePoints', {Text = 'Saved points', Values = labels(), Multi = false,
        Callback = function(value) selected = tonumber(tostring(value):match('^(%d+)')) end})

    local function refresh(wanted)
        local option = H.UI.Options.EH_TrinketRoutePoints
        local values = labels()
        if option then
            option:SetValues(values)
            option:SetValue(values[math.clamp(wanted or 1, 1, #values)])
        end
    end
    local function changed(wanted)
        reset()
        refresh(wanted)
        drawMarkers()
        save()
    end

    group:AddButton({Text = 'Add point at my position', Func = function()
        local root = C.Root() if not root then return end
        local p = root.Position route[#route + 1] = {p.X, p.Y, p.Z} changed(#route)
    end})
    group:AddButton({Text = 'Replace selected with my position', Func = function()
        local root = C.Root() if not root or not selected or not route[selected] then return end
        local p = root.Position route[selected] = {p.X, p.Y, p.Z} changed(selected)
    end})
    group:AddButton({Text = 'Remove selected point', Func = function()
        if not selected or not route[selected] then return end
        local i = selected table.remove(route, i) changed(i)
    end})
    group:AddButton({Text = 'Move selected earlier', Func = function()
        if not selected or selected <= 1 or not route[selected] then return end
        local i = selected route[i - 1], route[i] = route[i], route[i - 1] changed(i - 1)
    end})
    group:AddButton({Text = 'Move selected later', Func = function()
        if not selected or selected >= #route then return end
        local i = selected route[i + 1], route[i] = route[i], route[i + 1] changed(i + 1)
    end})
    group:AddButton({Text = 'Save route', Func = save})
    group:AddSlider('EH_TrinketPointWait', {Text = 'Selected point wait (0 = global)', Default = 0,
        Min = 0, Max = 30, Rounding = 0, Suffix = ' s', Callback = function(value)
            if selected and route[selected] then route[selected][4] = value > 0 and value or nil changed(selected) end
        end})
    refresh(1)
    drawMarkers()

    local previousStart = F.Start
    function F.Start()
        if not waiting or tick() >= waitUntil then waiting = false waitUntil = 0 end
        return previousStart()
    end

    local function targetIsLocal(root, target)
        if not root or not F.Allowed(target) then return false end
        local part = C.DropPart(target)
        return part and (root.Position - part.Position).Magnitude <= cfg.TrinketRouteLootRadius
    end

    local function nearestLocal(root)
        local target = F.Nearest()
        if not target then return nil end
        local part = C.DropPart(target)
        if not part then return nil end
        if (root.Position - part.Position).Magnitude <= cfg.TrinketRouteLootRadius then return target end
        return nil
    end

    local previousStep = F.Step
    function F.Step(dt)
        if H.State.Unloaded or H.State.Ready == false or not H.State.Running or cfg.AutoSell
            or (cfg.AutoFarmSell and H.State.FarmSellPhase == 'SELL') then return end
        if not cfg.TrinketExplore or #route == 0 then return previousStep(dt) end
        local root, hum = C.Root(), C.Humanoid()
        if not root or not hum or hum.Health <= 0 then return previousStep(dt) end
        if waiting then
            if tick() < waitUntil then
                H.State.Status = 'WAITING AT ROUTE POINT ' .. index
                C.Noclip(true)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                return
            end
            waiting = false
        end

        -- A streamed drop on the other side of the map used to make F.Nearest()
        -- return truthy forever, which prevented the route index from advancing.
        -- While following a saved route, only let loot near the current character
        -- position interrupt the path. Distant/stale streamed drops are ignored
        -- until the route reaches their area naturally.
        local current = H.State.CurrentTarget
        if current and not targetIsLocal(root, current) then
            F.ClearTarget()
            current = nil
        end
        if current or nearestLocal(root) then return previousStep(dt) end

        if index == #route and H.ServerCycle and H.ServerCycle.OnLootComplete() then return end
        F.ClearTarget()
        index = index % #route + 1
        local p = route[index]
        local destination = Vector3.new(p[1], p[2], p[3])
        C.Noclip(true)
        if not C.Teleport(destination) then return end
        waiting = true
        local pointWait = tonumber(p[4]) or cfg.TrinketRouteWait
        waitUntil = tick() + pointWait
        H.State.Status = 'ROUTE POINT ' .. index .. '/' .. #route
        drawMarkers()
        print('[EndHub Route] point=' .. index .. '/' .. #route .. ' | wait=' .. pointWait .. ' | radius=' .. cfg.TrinketRouteLootRadius .. ' | position=' .. tostring(destination))
        if not streaming then
            streaming = true
            task.spawn(function()
                pcall(function() H.S.Player:RequestStreamAroundAsync(destination, 2) end)
                streaming = false
            end)
        end
    end
    function H.ResumeTrinketRouteAfterDeath()
        if index > 0 and route[index] then waiting = true waitUntil = tick() + (tonumber(route[index][4]) or cfg.TrinketRouteWait) end
    end
    local oldUnload = H.Unload
    function H:Unload() clearMarkers() return oldUnload(self) end
    print('[EndHub] saved trinket route loaded | points=' .. #route .. ' | wait=' .. cfg.TrinketRouteWait .. ' | local loot radius=' .. cfg.TrinketRouteLootRadius)
end
