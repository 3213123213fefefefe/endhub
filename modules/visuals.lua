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

    local npcESP = {}
    local playerESP = {}

    local function textDrawing()
        local d = Drawing.new("Text")
        d.Size = 14
        d.Center = true
        d.Outline = true
        d.Visible = false
        H.Drawings[#H.Drawings + 1] = d
        return d
    end

    local function clearMap(map)
        for key, d in pairs(map) do
            pcall(function() d.Visible = false d:Remove() end)
            map[key] = nil
        end
    end

    function V.Reset()
        H.Config.NoFog = false
        H.Config.Fullbright = false
        H.Config.NPCESP = false
        H.Config.PlayerESP = false
        pcall(function()
            Lighting.FogEnd = oldLighting.FogEnd
            Lighting.FogStart = oldLighting.FogStart
            Lighting.Brightness = oldLighting.Brightness
            Lighting.ClockTime = oldLighting.ClockTime
            Lighting.GlobalShadows = oldLighting.GlobalShadows
            Lighting.Ambient = oldLighting.Ambient
            Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient
        end)
        clearMap(npcESP)
        clearMap(playerESP)
    end

    local function updateLighting()
        if H.Config.NoFog then
            Lighting.FogStart = 0
            Lighting.FogEnd = 1000000
            for _, o in ipairs(Lighting:GetChildren()) do
                if o:IsA("Atmosphere") then
                    o.Density = 0
                    o.Haze = 0
                elseif o:IsA("BlurEffect") then
                    o.Enabled = false
                end
            end
        end

        if H.Config.Fullbright then
            Lighting.Brightness = H.Config.FullbrightBrightness
            Lighting.ClockTime = H.Config.FullbrightClockTime
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.new(1,1,1)
            Lighting.OutdoorAmbient = Color3.new(1,1,1)
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
                    local v, on = cam:WorldToViewportPoint(p.Position + Vector3.new(0,2.5,0))
                    if on and v.Z > 0 then
                        local dist = root and math.floor((root.Position - p.Position).Magnitude) or 0
                        d.Text = npc.Name .. " [" .. tostring(dist) .. "]"
                        d.Position = Vector2.new(v.X, v.Y)
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

    local function updatePlayerESP()
        local cam = workspace.CurrentCamera
        local meRoot = C.Root()
        if not cam then return end

        if not H.Config.PlayerESP then
            for _, d in pairs(playerESP) do d.Visible = false end
            return
        end

        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= H.S.Player then
                local ch = plr.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                if root then
                    seen[plr] = true
                    local d = playerESP[plr]
                    if not d then d = textDrawing() playerESP[plr] = d end
                    local v, on = cam:WorldToViewportPoint(root.Position + Vector3.new(0,3,0))
                    if on and v.Z > 0 then
                        local dist = meRoot and math.floor((meRoot.Position-root.Position).Magnitude) or 0
                        d.Text = plr.Name .. " [" .. tostring(dist) .. "]"
                        d.Position = Vector2.new(v.X,v.Y)
                        d.Visible = true
                    else d.Visible = false end
                end
            end
        end
        for plr, d in pairs(playerESP) do
            if not seen[plr] then d.Visible = false end
        end
    end

    C.Connect(H.S.RunService.RenderStepped, function()
        if H.State.Unloaded then return end
        pcall(updateLighting)
        pcall(updateNPCESP)
        pcall(updatePlayerESP)
    end)
end
