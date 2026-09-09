return function(H)
    local B, C = H.Boss, H.Core
    local players = H.S.Players
    local rows, cacheTime = {}, -math.huge
    local placeholder = 'SELECT A BOSS / NPC'
    H.Config.BossDetectionRange = math.clamp(tonumber(H.Config.BossDetectionRange) or 500, 25, 5000)
    local function scan(force)
        if not force and tick() - cacheTime < 1 then return end
        cacheTime = tick()
        rows = {}
        local root = C.Root()
        if not root then return end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA('Humanoid') and obj.Health > 0 then
                local model = obj.Parent
                local part = model and model:IsA('Model') and C.NPCAnchor(model)
                if part and not players:GetPlayerFromCharacter(model)
                    and (root.Position - part.Position).Magnitude <= H.Config.BossDetectionRange then
                    rows[#rows + 1] = {
                        Model = model, Humanoid = obj,
                        Key = model.Name .. ' | ' .. model:GetFullName(),
                    }
                end
            end
        end
        table.sort(rows, function(a,b) return a.Key < b.Key end)
    end
    function B.GetNPCNames()
        scan(true)
        local values, seen = {placeholder}, {}
        for _, row in ipairs(rows) do
            if not seen[row.Key] then seen[row.Key] = true values[#values + 1] = row.Key end
        end
        return values
    end
    function B.FindTarget()
        scan(false)
        local wanted = H.Config.BossTargetName
        if not wanted or wanted == placeholder or wanted == 'AUTO: Highest MaxHealth' then return nil end
        local root = C.Root()
        if not root then return nil end
        local best, distance = nil, math.huge
        for _, row in ipairs(rows) do
            local model, hum = row.Model, row.Humanoid
            if row.Key == wanted and model.Parent and hum.Health > 0 then
                local part = C.NPCAnchor(model)
                if part then
                    local d = root and (root.Position - part.Position).Magnitude or 0
                    if d <= H.Config.BossDetectionRange and d < distance then best, distance = model, d end
                end
            end
        end
        return best
    end
    local oldStart = B.Start
    function B.Start()
        local wanted = H.Config.BossTargetName
        if not wanted or wanted == placeholder or wanted == 'AUTO: Highest MaxHealth' then
            B.Stop()
            H.State.BossStatus = 'SELECT AN EXACT TARGET FIRST'
            local toggle = H.UI.Toggles.EH_BossBot
            if toggle and toggle.Value then toggle:SetValue(false) end
            print('[EndHub Boss] start blocked: select an exact target')
            return
        end
        print('[EndHub Boss] selected target=' .. wanted .. ' | weapon=' .. tostring(H.Config.BossWeaponName))
        return oldStart()
    end
    local function refresh(logRows)
        local wanted = H.Config.BossTargetName
        local values = B.GetNPCNames()
        if wanted and wanted ~= placeholder and wanted ~= 'AUTO: Highest MaxHealth' and string.find(wanted, ' | ', 1, true) then
            local present = false
            for _, value in ipairs(values) do if value == wanted then present = true break end end
            if not present then values[#values + 1] = wanted end
        else wanted = placeholder end
        local option = H.UI.Options.EH_BossTarget
        if option then option:SetValues(values) option:SetValue(wanted) end
        H.Config.BossTargetName = wanted
        if logRows then
            local root = C.Root()
            for _, row in ipairs(rows) do
                local part = C.NPCAnchor(row.Model)
                local d = root and part and math.floor((root.Position - part.Position).Magnitude) or -1
                print('[EndHub BossScan] ' .. row.Key .. ' | HP=' .. row.Humanoid.Health .. '/' .. row.Humanoid.MaxHealth .. ' | distance=' .. d)
            end
            print('[EndHub BossScan] loaded NPC candidates=' .. #rows .. ' | radius=' .. H.Config.BossDetectionRange)
        end
    end
    local group = H.UI.Tabs.Boss:AddLeftGroupbox('Exact Target Detection')
    group:AddSlider('EH_BossDetectionRange', {
        Text = 'NPC detection radius', Default = H.Config.BossDetectionRange,
        Min = 25, Max = 5000, Rounding = 0, Suffix = ' studs',
        Callback = function(value)
            H.Config.BossDetectionRange = value
            cacheTime = -math.huge
            B.Runtime.Target = nil
            B.Runtime.SafeDirection = nil
            refresh(false)
        end,
    })
    group:AddButton({Text = 'Scan loaded NPCs / write diagnostic', Func = function() refresh(true) end})
    group:AddLabel('Select the boss by name and path in Boss / NPC target. This lists loaded NPCs, not confirmed bosses. Players are excluded.', true)
    group:AddLabel('If the boss is missing, approach its arena and scan again. Identical paths select the nearest matching NPC.', true)
    refresh(false)
    print('[EndHub] explicit boss target selection loaded; highest-HP automatic targeting disabled')
end
