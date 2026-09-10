return function(H)
    local B, M, C = H.Boss, H.MobFarm, H.Core
    if not B or not M or type(M.Classify) ~= "function" then
        error("EndHub: boss aggressive detector requires Boss and MobFarm")
    end

    local RANGE = 1500
    H.Config.BossDetectionRange = RANGE

    local function candidates(logRows)
        local root = C.Root()
        local folder = workspace:FindFirstChild("Monsters")
        local rows, seen = {}, {}
        if root and folder then
            for _, model in ipairs(folder:GetDescendants()) do
                if model:IsA("Model") and not seen[model] then
                    seen[model] = true
                    local aggressive, reason, meta = M.Classify(model)
                    local anchor = aggressive and C.NPCAnchor(model) or nil
                    local distance = anchor and (root.Position - anchor.Position).Magnitude or math.huge
                    if aggressive and distance <= RANGE then
                        rows[#rows + 1] = {
                            Model = model,
                            Distance = distance,
                            MaxHealth = tonumber(meta.Humanoid.MaxHealth) or 0,
                            Health = tonumber(meta.Humanoid.Health) or 0,
                            Meta = meta,
                        }
                    elseif logRows and (model:FindFirstChildWhichIsA("Humanoid") or model:FindFirstChild("Stats")) then
                        print(string.format("[EndHub Boss] reject | %s | %s | dist=%.1f",
                            model:GetFullName(), tostring(reason), distance))
                    end
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.MaxHealth ~= b.MaxHealth then return a.MaxHealth > b.MaxHealth end
            if a.Health ~= b.Health then return a.Health > b.Health end
            return a.Distance < b.Distance
        end)
        H.State.BossCandidates = #rows
        if logRows then
            for _, row in ipairs(rows) do
                print(string.format("[EndHub Boss] AGGRESSIVE CANDIDATE | %s | dist=%.1f | hp=%.0f/%.0f | dmg=%.1f | aggro=%.1f",
                    row.Model:GetFullName(), row.Distance, row.Health, row.MaxHealth,
                    row.Meta.BaseDamage or 0, row.Meta.AggroRange or 0))
            end
            print("[EndHub Boss] scan complete | range=1500 | aggressive candidates=" .. #rows)
        end
        return rows
    end

    B.Candidates = candidates

    function B.GetNPCNames()
        local names, seen = {"AUTO: Highest MaxHealth"}, {}
        for _, row in ipairs(candidates(false)) do
            local name = row.Model.Name
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
        return names
    end

    function B.FindTarget()
        local rows = candidates(false)
        local wanted = tostring(H.Config.BossTargetName or "AUTO: Highest MaxHealth")
        if wanted == "" or wanted == "AUTO: Highest MaxHealth" then
            return rows[1] and rows[1].Model or nil
        end
        local best
        for _, row in ipairs(rows) do
            if row.Model.Name == wanted and (not best or row.Distance < best.Distance) then best = row end
        end
        return best and best.Model or nil
    end

    -- The original boss loop retains a living target. Invalidate it whenever
    -- it stops satisfying the same strict aggressive rule or leaves 1500 studs.
    C.Connect(H.S.RunService.Heartbeat, function()
        if H.State.Unloaded or not H.Config.BossBotEnabled then return end
        local target = B.Runtime and B.Runtime.Target
        if not target then return end
        local aggressive = M.Classify(target)
        local root, anchor = C.Root(), C.NPCAnchor(target)
        local inRange = root and anchor and (root.Position - anchor.Position).Magnitude <= RANGE
        if not aggressive or not inRange then
            B.Runtime.Target = nil
            H.State.BossStatus = aggressive and "BOSS LEFT 1500 STUD RANGE" or "TARGET IS NOT AGGRESSIVE"
        end
    end)

    print("[EndHub] boss detector patched | aggressive monsters only | range=1500")
end
