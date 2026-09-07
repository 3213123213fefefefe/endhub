return function(H)
    H.Boss = {}
    local B = H.Boss
    local C = H.Core
    local Player = H.S.Player
    local VIM = H.S.VIM
    local RunService = H.S.RunService

    H.Config.BossBotEnabled = false
    H.Config.BossTargetName = H.Config.BossTargetName or "AUTO: Highest MaxHealth"
    H.Config.BossWeaponName = H.Config.BossWeaponName or "Use Equipped"
    H.Config.BossDistance = tonumber(H.Config.BossDistance) or 55
    H.Config.BossDepth = tonumber(H.Config.BossDepth) or 18
    H.Config.BossShotInterval = tonumber(H.Config.BossShotInterval) or 0.45
    if H.Config.BossAutoShoot == nil then H.Config.BossAutoShoot = true end
    if H.Config.BossLockAim == nil then H.Config.BossLockAim = true end
    if H.Config.BossNoclip == nil then H.Config.BossNoclip = true end
    H.Config.BossAimPart = H.Config.BossAimPart or "Head"

    H.State.BossStatus = H.State.BossStatus or "IDLE"
    H.State.BossTarget = H.State.BossTarget or "None"
    H.State.BossHP = H.State.BossHP or "--/--"
    H.State.BossWeapon = H.State.BossWeapon or "None"
    H.State.BossDistance = H.State.BossDistance or 0

    local R = {
        Target = nil,
        SafeDirection = nil,
        LastShot = 0,
        LastEquip = 0,
    }
    B.Runtime = R

    local function humanoidOf(model)
        return model and model:FindFirstChildWhichIsA("Humanoid") or nil
    end

    local function alive(model)
        local hum = humanoidOf(model)
        return model and model.Parent and hum and hum.Health > 0
    end

    local function combatAnchor(model)
        if not model then return nil end
        local wanted = tostring(H.Config.BossAimPart or "Head")
        local p = model:FindFirstChild(wanted)
        if p and p:IsA("BasePart") then return p end
        return model:FindFirstChild("Head")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("HumanoidRootPart")
            or C.NPCAnchor(model)
    end

    function B.GetNPCNames()
        local folder = C.NPCFolder()
        local rows = {}
        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                if npc:IsA("Model") then
                    local hum = humanoidOf(npc)
                    if hum and hum.Health > 0 and C.NPCAnchor(npc) then
                        rows[#rows + 1] = {Name = npc.Name, Max = hum.MaxHealth or 0}
                    end
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.Max == b.Max then return string.lower(a.Name) < string.lower(b.Name) end
            return a.Max > b.Max
        end)

        local names = {"AUTO: Highest MaxHealth"}
        local seen = {}
        for _, row in ipairs(rows) do
            if not seen[row.Name] then
                seen[row.Name] = true
                names[#names + 1] = row.Name
            end
        end
        return names
    end

    function B.GetWeaponNames()
        local names = {"Use Equipped"}
        local seen = {}
        local function scan(container)
            if not container then return end
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and not seen[obj.Name] then
                    seen[obj.Name] = true
                    names[#names + 1] = obj.Name
                end
            end
        end
        scan(C.Character())
        scan(Player:FindFirstChildOfClass("Backpack") or Player:FindFirstChild("Backpack"))
        table.sort(names, function(a, b)
            if a == "Use Equipped" then return true end
            if b == "Use Equipped" then return false end
            return string.lower(a) < string.lower(b)
        end)
        return names
    end

    function B.GetWeaponTool(equip)
        local ch = C.Character()
        if not ch then return nil end

        local selected = tostring(H.Config.BossWeaponName or "Use Equipped")
        if selected == "Use Equipped" then
            return ch:FindFirstChildWhichIsA("Tool")
        end

        local tool = ch:FindFirstChild(selected)
        if tool and tool:IsA("Tool") then return tool end

        local backpack = Player:FindFirstChildOfClass("Backpack") or Player:FindFirstChild("Backpack")
        tool = backpack and backpack:FindFirstChild(selected)
        if tool and tool:IsA("Tool") and equip then
            local hum = C.Humanoid()
            if hum then
                pcall(function() hum:EquipTool(tool) end)
                task.wait()
                local equipped = ch:FindFirstChild(selected)
                if equipped and equipped:IsA("Tool") then return equipped end
            end
        end
        return tool
    end

    local function autoTarget()
        local folder = C.NPCFolder()
        if not folder then return nil end
        local best, bestMax, bestHealth = nil, -math.huge, -math.huge
        for _, npc in ipairs(folder:GetChildren()) do
            if npc:IsA("Model") and alive(npc) and C.NPCAnchor(npc) then
                local hum = humanoidOf(npc)
                local maxHealth = tonumber(hum.MaxHealth) or 0
                local health = tonumber(hum.Health) or 0
                if maxHealth > bestMax or (maxHealth == bestMax and health > bestHealth) then
                    best, bestMax, bestHealth = npc, maxHealth, health
                end
            end
        end
        return best
    end

    function B.FindTarget()
        local folder = C.NPCFolder()
        if not folder then return nil end
        local wanted = tostring(H.Config.BossTargetName or "AUTO: Highest MaxHealth")
        if wanted == "" or wanted == "AUTO: Highest MaxHealth" then
            return autoTarget()
        end
        local exact = folder:FindFirstChild(wanted)
        if exact and exact:IsA("Model") and alive(exact) then return exact end
        return nil
    end

    local function acquireTarget()
        local target = B.FindTarget()
        R.Target = target
        R.SafeDirection = nil
        if target then
            local root = C.Root()
            local anchor = C.NPCAnchor(target)
            if root and anchor then
                local flat = Vector3.new(root.Position.X - anchor.Position.X, 0, root.Position.Z - anchor.Position.Z)
                if flat.Magnitude < 1 then flat = Vector3.new(0, 0, 1) end
                R.SafeDirection = flat.Unit
            end
        end
        return target
    end

    local function moveMouseToAim(aimPos)
        local cam = workspace.CurrentCamera
        if not cam then return false end
        local v, onScreen = cam:WorldToViewportPoint(aimPos)
        if not onScreen or v.Z <= 0 then return false end
        pcall(function()
            VIM:SendMouseMoveEvent(v.X, v.Y, game)
        end)
        return true
    end

    local function fireWeapon(aimPos)
        local tool = B.GetWeaponTool(true)
        H.State.BossWeapon = tool and tool.Name or "None"
        moveMouseToAim(aimPos)

        if tool and tool.Parent == C.Character() then
            local ok = pcall(function() tool:Activate() end)
            if ok then return true end
        end

        local cam = workspace.CurrentCamera
        if not cam then return false end
        local v, onScreen = cam:WorldToViewportPoint(aimPos)
        if not onScreen then return false end
        return pcall(function()
            VIM:SendMouseButtonEvent(v.X, v.Y, 0, true, game, 0)
            task.wait(0.035)
            VIM:SendMouseButtonEvent(v.X, v.Y, 0, false, game, 0)
        end)
    end

    function B.Start()
        if H.State.Unloaded then return end
        if H.Farm and H.State.Running then H.Farm.Stop() end
        if H.Sell and H.Config.AutoSell then H.Sell.Stop() end
        H.Config.AutoFarmSell = false
        H.Config.MovementFly = false
        H.Config.BossBotEnabled = true
        R.Target = nil
        R.SafeDirection = nil
        R.LastShot = 0
        H.State.BossStatus = "ACQUIRING TARGET"
    end

    function B.Stop()
        H.Config.BossBotEnabled = false
        R.Target = nil
        R.SafeDirection = nil
        H.State.BossStatus = "IDLE"
        H.State.BossTarget = "None"
        H.State.BossHP = "--/--"
        if not H.Config.MovementNoclip and not H.State.Running then
            C.Noclip(false)
        end
    end

    function B.Toggle()
        if H.Config.BossBotEnabled then B.Stop() else B.Start() end
    end

    function B.Reset()
        B.Stop()
    end

    C.Connect(RunService.RenderStepped, function()
        if H.State.Unloaded or not H.Config.BossBotEnabled then return end

        local root = C.Root()
        if not root then
            H.State.BossStatus = "WAIT CHARACTER"
            return
        end

        local target = R.Target
        if not alive(target) then
            target = acquireTarget()
        end
        if not target then
            H.State.BossStatus = "WAITING FOR BOSS"
            H.State.BossTarget = "None"
            H.State.BossHP = "--/--"
            return
        end

        local hum = humanoidOf(target)
        local body = C.NPCAnchor(target)
        local aim = combatAnchor(target)
        if not hum or not body or not aim then
            R.Target = nil
            H.State.BossStatus = "TARGET INVALID"
            return
        end

        H.State.BossTarget = target.Name
        H.State.BossHP = string.format("%d/%d", math.max(0, math.floor(hum.Health)), math.max(0, math.floor(hum.MaxHealth)))

        if not R.SafeDirection then
            local flat = Vector3.new(root.Position.X - body.Position.X, 0, root.Position.Z - body.Position.Z)
            if flat.Magnitude < 1 then flat = Vector3.new(0, 0, 1) end
            R.SafeDirection = flat.Unit
        end

        local distance = math.max(5, tonumber(H.Config.BossDistance) or 55)
        local depth = math.max(0, tonumber(H.Config.BossDepth) or 18)
        local desired = body.Position + (R.SafeDirection * distance) - Vector3.new(0, depth, 0)
        H.State.BossDistance = (root.Position - body.Position).Magnitude

        if H.Config.BossNoclip then C.Noclip(true) end

        root.CFrame = CFrame.lookAt(desired, aim.Position)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        local cam = workspace.CurrentCamera
        if H.Config.BossLockAim and cam then
            pcall(function()
                cam.CFrame = CFrame.lookAt(cam.CFrame.Position, aim.Position)
            end)
        end

        B.GetWeaponTool(true)

        if H.Config.BossAutoShoot then
            local interval = math.max(0.08, tonumber(H.Config.BossShotInterval) or 0.45)
            if tick() - R.LastShot >= interval then
                R.LastShot = tick()
                H.State.BossStatus = "ATTACKING"
                fireWeapon(aim.Position)
            end
        else
            H.State.BossStatus = "AIMING / MANUAL FIRE"
            moveMouseToAim(aim.Position)
        end
    end)

    print("[EndHub] boss bot loaded")
end
