return function(H)
    local F, C, cfg = H.Farm, H.Core, H.Config
    local mapKey = tostring(game.PlaceId)
    cfg.TrinketExplore = cfg.TrinketExplore ~= false
    cfg.TrinketRoutes = type(cfg.TrinketRoutes) == 'table' and cfg.TrinketRoutes or {}
    cfg.TrinketRoutes[mapKey] = type(cfg.TrinketRoutes[mapKey]) == 'table' and cfg.TrinketRoutes[mapKey] or {}
    cfg.TrinketRouteWait = math.clamp(tonumber(cfg.TrinketRouteWait) or 1, 1, 10)
    local route = cfg.TrinketRoutes[mapKey]
    local index, waitUntil, selected = 0, 0, nil
    local waiting = false
    local streaming = false
    function H.GetTrinketRouteStatus()
        return {Index = index, Total = #route, Remaining = waiting and math.max(0, waitUntil - tick()) or 0}
    end
    local function save()
        if H.PersistenceManager and H.PersistenceManager.SaveConfig then
            local ok, result = pcall(H.PersistenceManager.SaveConfig, true)
            if not ok or result == false then
                warn('[EndHub Route] could not save route to disk')
                return false
            end
            print('[EndHub Route] saved | map=' .. mapKey .. ' | points=' .. #route)
            return true
        end
        warn('[EndHub Route] persistence unavailable')
        return false
    end
    local function reset()
        index = 0
        waitUntil = 0
        waiting = false
        F.ClearTarget()
    end
    local function labels()
        local values = {}
        for i, p in ipairs(route) do
            values[#values + 1] = string.format('%d | %.1f, %.1f, %.1f', i, p[1], p[2], p[3])
        end
        if #values == 0 then values[1] = 'No saved points' end
        return values
    end
    -- Ignore malformed saved entries rather than teleporting to invalid coordinates.
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
    group:AddToggle('EH_TrinketExplore', {
        Text = 'Use saved search points', Default = cfg.TrinketExplore,
        Callback = function(value) cfg.TrinketExplore = value reset() end,
    })
    group:AddSlider('EH_TrinketRouteWait', {
        Text = 'Wait before looting at each point', Default = cfg.TrinketRouteWait,
        Min = 1, Max = 10, Rounding = 0, Suffix = ' s',
        Callback = function(value) cfg.TrinketRouteWait = value end,
    })
    group:AddDropdown('EH_TrinketRoutePoints', {
        Text = 'Saved points (visit order)', Values = labels(), Multi = false,
        Callback = function(value) selected = tonumber(tostring(value):match('^(%d+)')) end,
    })
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
        save()
    end
    group:AddButton({Text = 'Add point at my position', Func = function()
        local root = C.Root()
        if not root then return end
        local p = root.Position
        route[#route + 1] = {p.X, p.Y, p.Z}
        changed(#route)
    end})
    group:AddButton({Text = 'Replace selected with my position', Func = function()
        local root = C.Root()
        if not root or not selected or not route[selected] then return end
        local p = root.Position
        route[selected] = {p.X, p.Y, p.Z}
        changed(selected)
    end})
    group:AddButton({Text = 'Remove selected point', Func = function()
        if not selected or not route[selected] then return end
        local i = selected
        table.remove(route, i)
        changed(i)
    end})
    group:AddButton({Text = 'Move selected earlier', Func = function()
        if not selected or selected <= 1 or not route[selected] then return end
        local i = selected
        route[i - 1], route[i] = route[i], route[i - 1]
        changed(i - 1)
    end})
    group:AddButton({Text = 'Move selected later', Func = function()
        if not selected or selected >= #route then return end
        local i = selected
        route[i + 1], route[i] = route[i], route[i + 1]
        changed(i + 1)
    end})
    group:AddButton({Text = 'Save route and wait time', Func = save})
    group:AddLabel('Points are saved per map. The cycle repeats the full route while collecting or detecting matching items; hops only after a complete empty lap.', true)
    refresh(1)
    local previousStart = F.Start
    function F.Start()
        -- Preserve the next route point across a sale and return to the collection area.
        -- A brief role check also preserves an unfinished streaming wait.
        if not waiting or tick() >= waitUntil then
            waiting = false
            waitUntil = 0
        end
        return previousStart()
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
        if F.Allowed(H.State.CurrentTarget) or F.Nearest() then return previousStep(dt) end
        if index == #route and H.ServerCycle and H.ServerCycle.OnLootComplete() then return end
        F.ClearTarget()
        index = index % #route + 1
        local p = route[index]
        local destination = Vector3.new(p[1], p[2], p[3])
        C.Noclip(true)
        if not C.Teleport(destination) then return end
        waiting = true
        waitUntil = tick() + cfg.TrinketRouteWait
        H.State.Status = 'ROUTE POINT ' .. index .. '/' .. #route
        print('[EndHub Route] point=' .. index .. '/' .. #route .. ' | wait=' .. cfg.TrinketRouteWait
            .. ' | position=' .. tostring(destination))
        if not streaming then
            streaming = true
            task.spawn(function()
                pcall(function() H.S.Player:RequestStreamAroundAsync(destination, 2) end)
                streaming = false
            end)
        end
    end
    print('[EndHub] saved trinket route loaded | points=' .. #route .. ' | wait=' .. cfg.TrinketRouteWait)
end
