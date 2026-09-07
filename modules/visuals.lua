return function(H)
    H.Visuals = {}
    local V = H.Visuals
    local C = H.Core
    local Lighting = H.S.Lighting
    local Players = H.S.Players

    local oldLighting = {
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
    }

    local effectBackup = {}
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Atmosphere") then
            effectBackup[obj] = {Density = obj.Density, Haze = obj.Haze}
        elseif obj:IsA("BlurEffect") then
            effectBackup[obj] = {Enabled = obj.Enabled}
        end
    end

    local npcESP = {}
    local playerESP = {}
    local playerHighlights = {}
    local fogApplied = false
    local fullbrightApplied = false

    local function textDrawing()
        local d = Drawing.new("Text")
        d.Size = 14
        d.Center = true
        d.Outline = true
        d.Font = 2
        d.Visible = false
        H.Drawings[#H.Drawings + 1] = d
        return d
    end

    local function clearDrawings(map)
        for key, d in pairs(map) do
            pcall(function() d.Visible = false d:Remove() end)
            map[key] = nil
        end
    end

    local function clearHighlights()
        for plr, h in pairs(playerHighlights) do
            pcall(function() h:Destroy() end)
            playerHighlights[plr] = nil
        end
    end

    local function restoreFog()
        Lighting.FogEnd = oldLighting.FogEnd
        Lighting.FogStart = oldLighting.FogStart
        for obj, data in pairs(effectBackup) do
            if obj and obj.Parent then
                if obj:IsA("Atmosphere") then
                    obj.Density = data.Density
                    obj.Haze = data.Haze
                elseif obj:IsA("BlurEffect") then
                    obj.Enabled = data.Enabled
                end
            end
        end
        fogApplied = false
    end

    local function applyFogRemoval()
        Lighting.FogStart = 0
        Lighting.FogEnd = 1000000
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("Atmosphere") then
                if not effectBackup[obj] then effectBackup[obj] = {Density = obj.Density, Haze = obj.Haze} end
                obj.Density = 0
                obj.Haze = 0
            elseif obj:IsA("BlurEffect") then
                if not effectBackup[obj] then effectBackup[obj] = {Enabled = obj.Enabled} end
                obj.Enabled = false
            end
        end
        fogApplied = true
    end

    local function restoreFullbright()
        Lighting.Brightness = oldLighting.Brightness
        Lighting.ClockTime = oldLighting.ClockTime
        Lighting.GlobalShadows = oldLighting.GlobalShadows
        Lighting.Ambient = oldLighting.Ambient
        Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient
        fullbrightApplied = false
    end

    local function applyFullbright()
        local ambient = math.clamp(H.Config.FullbrightAmbient, 0, 1)
        Lighting.Brightness = H.Config.FullbrightBrightness
        Lighting.ClockTime = H.Config.FullbrightClockTime
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.new(ambient, ambient, ambient)
        Lighting.OutdoorAmbient = Color3.new(ambient, ambient, ambient)
        fullbrightApplied = true
    end

    function V.Reset()
        H.Config.NoFog = false
        H.Config.Fullbright = false
        H.Config.NPCESP = false
        H.Config.PlayerESP = false
        restoreFog()
        restoreFullbright()
        clearDrawings(npcESP)
        clearDrawings(playerESP)
        clearHighlights()
    end

    local function updateLighting()
        if H.Config.NoFog then
            applyFogRemoval()
        elseif fogApplied then
            restoreFog()
        end

        if H.Config.Fullbright then
            applyFullbright()
        elseif fullbrightApplied then
            restoreFullbright()
        end
    end

    local function updateNPCESP()
        local folder = C.NPCFolder()
        local cam = workspace.CurrentCamera
        local root = C.Root()
        if not cam then return end

        if not H.Config.NPCESP or not folder then
            for _, d in pairs(npcESP) do d.Visible = false end
            return
        end

        local seen = {}
        for _, npc in ipairs(folder:GetChildren()) do
            if npc:IsA("Model") then
                local p = C.NPCAnchor(npc)
                if p then
                    seen[npc] = true
                    local d = npcESP[npc]
                    if not d then d = textDrawing() npcESP[npc] = d end
                    local v, on = cam:WorldToViewportPoint(p.Position + Vector3.new(0, 2.5, 0))
                    if on and v.Z > 0 then
                        local dist = root and math.floor((root.Position - p.Position).Magnitude) or 0
                        d.Text = npc.Name .. "\n[" .. tostring(dist) .. " studs]"
                        d.Position = Vector2.new(v.X, v.Y)
                        pcall(function() d.Color = p.Color end)
                        d.Visible = true
                    else
                        d.Visible = false
                    end
                end
            end
        end
        for npc, d in pairs(npcESP) do
            if not seen[npc] or not npc.Parent then
                pcall(function() d:Remove() end)
                npcESP[npc] = nil
            end
        end
    end

    local function ensureHighlight(plr, ch)
        local h = playerHighlights[plr]
        if h and h.Parent == ch then return h end
        if h then pcall(function() h:Destroy() end) end
        h = Instance.new("Highlight")
        h.Name = "EndHub_PlayerESP"
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency = 0.88
        h.OutlineTransparency = 0.10
        h.FillColor = Color3.fromRGB(125, 85, 255)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.Parent = ch
        playerHighlights[plr] = h
        return h
    end

    local function updatePlayerESP()
        local cam = workspace.CurrentCamera
        if not cam then return end

        if not H.Config.PlayerESP then
            for _, d in pairs(playerESP) do d.Visible = false end
            clearHighlights()
            return
        end

        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= H.S.Player then
                local ch = plr.Character
                local root = C.Root(plr)
                local hum = C.Humanoid(plr)
                if ch and root and hum then
                    seen[plr] = true
                    ensureHighlight(plr, ch)
                    local d = playerESP[plr]
                    if not d then d = textDrawing() playerESP[plr] = d end
                    local v, on = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 3.6, 0))
                    if on and v.Z > 0 then
                        local parts = {plr.Name}
                        if H.Config.ESPShowRank then parts[#parts + 1] = "[" .. C.PlayerGrade(plr) .. "]" end
                        if H.Config.ESPShowDistance then
                            local dist = C.PlayerDistance(plr)
                            parts[#parts + 1] = dist == math.huge and "(?)" or ("(" .. math.floor(dist) .. "m)")
                        end
                        parts[#parts + 1] = "HP: " .. math.floor(hum.Health)
                        if H.Config.ESPShowEquipped then
                            parts[#parts + 1] = "\nEquipped: " .. C.EquippedName(plr)
                        end
                        d.Text = table.concat(parts, " ")
                        d.Position = Vector2.new(v.X, v.Y)
                        d.Color = Color3.new(1, 1, 1)
                        d.Visible = true
                    else
                        d.Visible = false
                    end
                end
            end
        end

        for plr, d in pairs(playerESP) do
            if not seen[plr] then
                d.Visible = false
                if playerHighlights[plr] then
                    pcall(function() playerHighlights[plr]:Destroy() end)
                    playerHighlights[plr] = nil
                end
            end
        end
    end

    C.Connect(H.S.RunService.RenderStepped, function()
        if H.State.Unloaded then return end
        pcall(updateLighting)
        pcall(updateNPCESP)
        pcall(updatePlayerESP)
    end)
end
