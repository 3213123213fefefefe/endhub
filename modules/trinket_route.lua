return function(H)
    local F, C, cfg = H.Farm, H.Core, H.Config
    local mapKey = tostring(game.PlaceId)
    cfg.TrinketExplore = cfg.TrinketExplore ~= false
    cfg.TrinketRoutes = type(cfg.TrinketRoutes) == 'table' and cfg.TrinketRoutes or {}
    cfg.TrinketRoutes[mapKey] = type(cfg.TrinketRoutes[mapKey]) == 'table' and cfg.TrinketRoutes[mapKey] or {}
    cfg.TrinketRouteWait = math.clamp(tonumber(cfg.TrinketRouteWait) or 1, 1, 10)
    cfg.TrinketRouteESP = cfg.TrinketRouteESP == true
    local route = cfg.TrinketRoutes[mapKey]
    local index, waitUntil, selected = 0, 0, nil
    local waiting = false
    local streaming = false
    local markerFolder, markers = nil, {}
    local refresh
    local updateMarkerColors
    local syncingUi = false
    local function pointWait(p)
        return math.clamp(tonumber(p and p[4]) or cfg.TrinketRouteWait, 0, 30)
    end
    function H.GetTrinketRouteStatus()
        return {Index = index, Total = #route, Remaining = waiting and math.max(0, waitUntil - tick()) or 0}
    end
    function H.ResumeTrinketRouteAfterDeath()
        if index < 1 or not route[index] then return false end
        waiting = true
        waitUntil = tick() + pointWait(route[index])
        updateMarkerColors()
        return true
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
            local waitText = p[4] ~= nil and string.format('%.1fs', pointWait(p)) or 'global'
            values[#values + 1] = string.format('%d | %.1f, %.1f, %.1f | wait %s',
                i, p[1], p[2], p[3], waitText)
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
        if valid then
            local customWait = tonumber(p[4])
            p[4] = customWait and customWait > 0 and math.clamp(customWait, 0.1, 30) or nil
        end
        if not valid then table.remove(route, i) end
    end
    local function clearMarkers()
        markers = {}
        if markerFolder then pcall(function() markerFolder:Destroy() end) end
        markerFolder = nil
    end
    local function markerColor(i)
        if i == selected then return Color3.fromRGB(255, 210, 40) end
        if i == index then return Color3.fromRGB(70, 255, 120) end
        return Color3.fromRGB(70, 190, 255)
    end
    updateMarkerColors = function()
        for i, marker in ipairs(markers) do
            local color = markerColor(i)
            pcall(function()
                marker.Part.Color = color
                marker.Text.TextColor3 = color
            end)
        end
    end
    local function rebuildMarkers()
        clearMarkers()
        if not cfg.TrinketRouteESP or not Instance or type(Instance.new) ~= 'function' then return end
        local ok, err = pcall(function()
            markerFolder = Instance.new('Folder')
            markerFolder.Name = 'EndHub_Route_' .. tostring(H.S.Player.UserId)
            markerFolder.Parent = workspace
            for i, p in ipairs(route) do
                local part = Instance.new('Part')
                part.Name = 'RoutePoint_' .. i
                part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
                part.Shape, part.Material = Enum.PartType.Ball, Enum.Material.Neon
                part.Size, part.Transparency = Vector3.new(1.6, 1.6, 1.6), 0.18
                part.Position, part.Color = Vector3.new(p[1], p[2], p[3]), markerColor(i)
                part.Parent = markerFolder

                local attachment = Instance.new('Attachment')
                attachment.Parent = part
                local billboard = Instance.new('BillboardGui')
                billboard.Name, billboard.AlwaysOnTop = 'Label', true
                billboard.Size, billboard.StudsOffsetWorldSpace = UDim2.fromOffset(150, 52), Vector3.new(0, 2.3, 0)
                billboard.MaxDistance, billboard.Parent = 100000, part
                local text = Instance.new('TextLabel')
                text.BackgroundTransparency, text.Size = 1, UDim2.fromScale(1, 1)
                text.Font, text.TextScaled, text.TextStrokeTransparency = Enum.Font.Code, true, 0.25
                text.TextColor3 = markerColor(i)
                text.Text = string.format('#%d  |  wait %.1fs', i, pointWait(p))
                text.Parent = billboard
                markers[i] = {Part = part, Attachment = attachment, Text = text}
            end
            for i = 1, #markers - 1 do
                local beam = Instance.new('Beam')
                beam.Name, beam.Attachment0, beam.Attachment1 = 'ToPoint_' .. (i + 1), markers[i].Attachment, markers[i + 1].Attachment
                beam.FaceCamera, beam.Width0, beam.Width1 = true, 0.12, 0.12
                beam.Color = ColorSequence.new(Color3.fromRGB(70, 190, 255))
                beam.Transparency, beam.Parent = NumberSequence.new(0.25), markerFolder
            end
        end)
        if not ok then clearMarkers() warn('[EndHub Route] marker error: ' .. tostring(err)) end
    end
    H.RouteVisuals = {Refresh = rebuildMarkers, Reset = clearMarkers}
    local group = H.UI.Tabs.Botting:AddLeftGroupbox('Trinket Route')
    group:AddToggle('EH_TrinketExplore', {
        Text = 'Use saved search points', Default = cfg.TrinketExplore,
        Callback = function(value) cfg.TrinketExplore = value reset() end,
    })
    group:AddToggle('EH_TrinketRouteESP', {
        Text = 'Show numbered route points', Default = cfg.TrinketRouteESP,
        Callback = function(value) cfg.TrinketRouteESP = value rebuildMarkers() end,
    })
    group:AddSlider('EH_TrinketRouteWait', {
        Text = 'Wait before looting at each point', Default = cfg.TrinketRouteWait,
        Min = 1, Max = 10, Rounding = 0, Suffix = ' s',
        Callback = function(value) cfg.TrinketRouteWait = value rebuildMarkers() end,
    })
    group:AddDropdown('EH_TrinketRoutePoints', {
        Text = 'Saved points (visit order)', Values = labels(), Multi = false,
        Callback = function(value)
            selected = tonumber(tostring(value):match('^(%d+)'))
            if syncingUi then return end
            local option = H.UI.Options.EH_TrinketRoutePointWait
            syncingUi = true
            if option and option.SetValue then option:SetValue(route[selected] and (tonumber(route[selected][4]) or 0) or 0) end
            syncingUi = false
            updateMarkerColors()
        end,
    })
    group:AddSlider('EH_TrinketRoutePointWait', {
        Text = 'Selected point wait (0 = global)', Default = 0,
        Min = 0, Max = 30, Rounding = 1, Suffix = ' s',
        Callback = function(value)
            if syncingUi or not selected or not route[selected] then return end
            route[selected][4] = value > 0 and value or nil
            refresh(selected)
            rebuildMarkers()
        end,
    })
    refresh = function(wanted)
        local option = H.UI.Options.EH_TrinketRoutePoints
        local values = labels()
        syncingUi = true
        if option then
            option:SetValues(values)
            option:SetValue(values[math.clamp(wanted or 1, 1, #values)])
        end
        selected = tonumber(tostring(values[math.clamp(wanted or 1, 1, #values)]):match('^(%d+)'))
        local waitOption = H.UI.Options.EH_TrinketRoutePointWait
        if waitOption and waitOption.SetValue then
            waitOption:SetValue(route[selected] and (tonumber(route[selected][4]) or 0) or 0)
        end
        syncingUi = false
        updateMarkerColors()
    end
    local function changed(wanted)
        reset()
        refresh(wanted)
        rebuildMarkers()
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
    group:AddButton({Text = 'Save route and wait times', Func = save})
    group:AddLabel('Points are saved per map. The cycle repeats the full route while collecting or detecting matching items; hops only after a complete empty lap.', true)
    refresh(1)
    rebuildMarkers()
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
        local delay = pointWait(p)
        waitUntil = tick() + delay
        updateMarkerColors()
        H.State.Status = 'ROUTE POINT ' .. index .. '/' .. #route
        print('[EndHub Route] point=' .. index .. '/' .. #route .. ' | wait=' .. delay
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
