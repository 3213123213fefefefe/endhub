return function(H)
    local C = H.Core
    local Player = H.S.Player
    local VIM = H.S.VIM
    local RunService = H.S.RunService

    H.MobFarm = H.MobFarm or {}
    local M = H.MobFarm

    H.Config.MobFarmEnabled = false
    H.Config.MobFarmWeaponName = H.Config.MobFarmWeaponName or "Use Equipped"
    H.Config.MobFarmMoveMode = H.Config.MobFarmMoveMode or "Fly"
    H.Config.MobFarmDetectionRange = tonumber(H.Config.MobFarmDetectionRange) or 600
    H.Config.MobFarmDistance = tonumber(H.Config.MobFarmDistance) or 32
    H.Config.MobFarmSafetyMargin = tonumber(H.Config.MobFarmSafetyMargin) or 10
    H.Config.MobFarmHeight = tonumber(H.Config.MobFarmHeight) or 8
    H.Config.MobFarmFlySpeed = tonumber(H.Config.MobFarmFlySpeed) or 95
    H.Config.MobFarmShotInterval = tonumber(H.Config.MobFarmShotInterval) or 0.45
    H.Config.MobFarmOrbitSpeed = tonumber(H.Config.MobFarmOrbitSpeed) or 35
    if H.Config.MobFarmLockAim == nil then H.Config.MobFarmLockAim = true end
    if H.Config.MobFarmNoclip == nil then H.Config.MobFarmNoclip = true end

    H.State.MobFarmStatus = H.State.MobFarmStatus or "IDLE"
    H.State.MobFarmTarget = H.State.MobFarmTarget or "None"
    H.State.MobFarmHP = H.State.MobFarmHP or "--/--"
    H.State.MobFarmCandidates = H.State.MobFarmCandidates or 0
    H.State.MobFarmObservedKills = H.State.MobFarmObservedKills or 0

    local R = {
        Target = nil,
        LastShot = 0,
        LastMove = 0,
        OrbitAngle = 0,
        OrbitSign = 1,
        LastHealth = nil,
        DodgeUntil = 0,
        CountedDeaths = setmetatable({}, {__mode = "k"}),
    }
    M.Runtime = R

    local function monstersFolder()
        return workspace:FindFirstChild("Monsters")
    end

    local function basicStats(model)
        local stats = model and model:FindFirstChild("Stats")
        return stats and stats:FindFirstChild("BasicStats") or nil
    end

    local function boolValue(folder, name)
        local v = folder and folder:FindFirstChild(name)
        if v and v:IsA("BoolValue") then return v.Value end
        return nil
    end

    local function numberValue(folder, name)
        local v = folder and folder:FindFirstChild(name)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return tonumber(v.Value) end
        return nil
    end

    local function enemyHumanoid(model)
        local hum = model and model:FindFirstChild("Enemy")
        if hum and hum:IsA("Humanoid") then return hum end
        return nil
    end

    function M.Classify(model)
        local folder = monstersFolder()
        if not folder or not model or not model:IsA("Model") or not model:IsDescendantOf(folder) then
            return false, "NOT IN WORKSPACE.MONSTERS"
        end
        if model.Name == "Training Dummy" then return false, "TRAINING DUMMY" end
        if model:FindFirstChild("NPCDialogueConfig", true) then return false, "HAS NPC DIALOGUE" end

        local hum = enemyHumanoid(model)
        if not hum or hum.Health <= 0 then return false, "NO LIVE ENEMY HUMANOID" end
        if not C.NPCAnchor(model) then return false, "NO COMBAT ANCHOR" end

        local basic = basicStats(model)
        if not basic then return false, "NO BASIC STATS" end
        if boolValue(basic, "CanAttack") ~= true then return false, "CANATTACK != TRUE" end
        if boolValue(basic, "Friendly") == true then return false, "FRIENDLY" end
        if boolValue(basic, "StopAttack") == true then return false, "STOPATTACK" end

        local damage = numberValue(basic, "BaseDamage") or 0
        local aggro = numberValue(basic, "AggroRange") or 0
        local attackRange = numberValue(basic, "AttackRange") or 0
        if damage <= 0 then return false, "NO DAMAGE" end
        if aggro <= 0 then return false, "NO AGGRO RANGE" end
        if attackRange <= 0 then return false, "NO ATTACK RANGE" end

        return true, "AGGRESSIVE", {
            Humanoid = hum,
            Basic = basic,
            BaseDamage = damage,
            AggroRange = aggro,
            AttackRange = attackRange,
        }
    end

    function M.Candidates(logRows)
        local folder = monstersFolder()
        local root = C.Root()
        local out = {}
        if folder and root then
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("Model") then
                    local ok, reason, meta = M.Classify(obj)
                    if ok then
                        local part = C.NPCAnchor(obj)
                        local d = part and (root.Position - part.Position).Magnitude or math.huge
                        if d <= math.max(25, tonumber(H.Config.MobFarmDetectionRange) or 600) then
                            out[#out + 1] = {Model = obj, Distance = d, Meta = meta}
                        end
                    elseif logRows and (obj:FindFirstChildWhichIsA("Humanoid") or obj:FindFirstChild("Stats")) then
                        print("[EndHub MobFarm] reject | " .. obj:GetFullName() .. " | " .. tostring(reason))
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.Distance < b.Distance end)
        H.State.MobFarmCandidates = #out
        if logRows then
            for _, row in ipairs(out) do
                print(string.format("[EndHub MobFarm] TARGET | %s | dist=%.1f | attackRange=%.1f | aggro=%.1f | dmg=%.1f",
                    row.Model:GetFullName(), row.Distance, row.Meta.AttackRange, row.Meta.AggroRange, row.Meta.BaseDamage))
            end
            print("[EndHub MobFarm] scan complete | aggressive candidates=" .. tostring(#out))
        end
        return out
    end

    local function targetAlive(model)
        local ok, _, meta = M.Classify(model)
        return ok and meta and meta.Humanoid.Health > 0
    end

    local function acquireTarget()
        local rows = M.Candidates(false)
        R.Target = rows[1] and rows[1].Model or nil
        return R.Target
    end

    function M.GetWeaponNames()
        local names, seen = {"Use Equipped"}, {}
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

    function M.GetWeaponTool(equip)
        local ch = C.Character()
        if not ch then return nil end
        local selected = tostring(H.Config.MobFarmWeaponName or "Use Equipped")
        if selected == "Use Equipped" then return ch:FindFirstChildWhichIsA("Tool") end
        local tool = ch:FindFirstChild(selected)
        if tool and tool:IsA("Tool") then return tool end
        local backpack = Player:FindFirstChildOfClass("Backpack") or Player:FindFirstChild("Backpack")
        tool = backpack and backpack:FindFirstChild(selected)
        if tool and tool:IsA("Tool") and equip then
            local hum = C.Humanoid()
            if hum then pcall(function() hum:EquipTool(tool) end) end
            return ch:FindFirstChild(selected) or tool
        end
        return tool
    end

    local function aimPart(model)
        if not model then return nil end
        return model:FindFirstChild("Head")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("HumanoidRootPart")
            or C.NPCAnchor(model)
    end

    local function moveMouseTo(pos)
        local cam = workspace.CurrentCamera
        if not cam then return false end
        local v, onScreen = cam:WorldToViewportPoint(pos)
        if not onScreen or v.Z <= 0 then return false end
        return pcall(function() VIM:SendMouseMoveEvent(v.X, v.Y, game) end)
    end

    local function hasLineOfSight(target, targetPart)
        local root = C.Root()
        if not root or not targetPart then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {C.Character()}
        params.IgnoreWater = true
        local result = workspace:Raycast(root.Position, targetPart.Position - root.Position, params)
        return result == nil or (result.Instance and result.Instance:IsDescendantOf(target))
    end

    local function fire(targetPart)
        local tool = M.GetWeaponTool(true)
        if not tool or tool.Parent ~= C.Character() then return false end
        moveMouseTo(targetPart.Position)
        local ok = pcall(function() tool:Activate() end)
        if ok then return true end
        local cam = workspace.CurrentCamera
        if not cam then return false end
        local v, onScreen = cam:WorldToViewportPoint(targetPart.Position)
        if not onScreen then return false end
        return pcall(function()
            VIM:SendMouseButtonEvent(v.X, v.Y, 0, true, game, 0)
            task.wait(0.035)
            VIM:SendMouseButtonEvent(v.X, v.Y, 0, false, game, 0)
        end)
    end

    local function desiredPosition(root, body, attackRange, dt)
        local safe = math.max(5, tonumber(H.Config.MobFarmDistance) or 32,
            attackRange + math.max(2, tonumber(H.Config.MobFarmSafetyMargin) or 10))
        if tick() < R.DodgeUntil then safe = safe + math.max(8, tonumber(H.Config.MobFarmSafetyMargin) or 10) end
        R.OrbitAngle = R.OrbitAngle + math.rad(tonumber(H.Config.MobFarmOrbitSpeed) or 35) * (dt or 0.03) * R.OrbitSign
        local dir = Vector3.new(math.cos(R.OrbitAngle), 0, math.sin(R.OrbitAngle))
        return body.Position + dir * safe + Vector3.new(0, math.max(0, tonumber(H.Config.MobFarmHeight) or 8), 0), safe
    end

    local function moveTo(root, destination, lookAt, dt, emergency)
        if emergency or tostring(H.Config.MobFarmMoveMode) == "TP" then
            C.Teleport(destination, lookAt)
            return
        end
        local now = tick()
        if now - R.LastMove < (1 / 30) then return end
        R.LastMove = now
        local delta = destination - root.Position
        if delta.Magnitude < 0.05 then return end
        local speed = math.max(10, tonumber(H.Config.MobFarmFlySpeed) or 95)
        local step = math.min(delta.Magnitude, speed * math.max(dt or 1/30, 1/60))
        local pos = root.Position + delta.Unit * step
        root.CFrame = CFrame.lookAt(pos, lookAt)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    function M.Start()
        if H.State.Unloaded then return end
        if H.Farm and H.State.Running then H.Farm.Stop() end
        if H.Sell and H.Config.AutoSell then H.Sell.Stop() end
        if H.Boss and H.Config.BossBotEnabled then H.Boss.Stop() end
        H.Config.AutoFarmSell = false
        H.Config.MovementFly = false
        H.Config.MobFarmEnabled = true
        R.Target = nil
        R.LastShot = 0
        R.LastHealth = nil
        R.DodgeUntil = 0
        H.State.MobFarmStatus = "SCANNING AGGRESSIVE MOBS"
    end

    function M.Stop()
        H.Config.MobFarmEnabled = false
        R.Target = nil
        H.State.MobFarmStatus = "IDLE"
        H.State.MobFarmTarget = "None"
        H.State.MobFarmHP = "--/--"
        if not H.Config.MovementNoclip and not H.State.Running and not H.Config.BossBotEnabled then
            C.Noclip(false)
        end
    end

    function M.Toggle()
        if H.Config.MobFarmEnabled then M.Stop() else M.Start() end
    end

    function M.Reset()
        M.Stop()
    end

    local function buildUI()
        if not H.UI or not H.UI.Window then return end
        local tab = H.UI.Window:AddTab("Mob Farm")
        H.UI.Tabs.MobFarm = tab
        local left = tab:AddLeftGroupbox("Aggressive Mobs Only")
        local right = tab:AddRightGroupbox("Avoid Hits / Ranged")
        local status = tab:AddRightGroupbox("Status")
        local Options = H.UI.Options
        local Toggles = H.UI.Toggles

        left:AddToggle("EH_MobFarmEnabled", {
            Text = "Automatic aggressive mob farm",
            Default = false,
            Callback = function(v) if v then M.Start() else M.Stop() end end,
        })
        left:AddDropdown("EH_MobFarmWeapon", {
            Text = "Weapon",
            Values = M.GetWeaponNames(),
            Default = H.Config.MobFarmWeaponName,
            Multi = false,
            Searchable = true,
            Callback = function(v) if type(v) == "string" then H.Config.MobFarmWeaponName = v end end,
        })
        left:AddButton({Text = "Refresh weapons", Func = function()
            if Options.EH_MobFarmWeapon then
                Options.EH_MobFarmWeapon:SetValues(M.GetWeaponNames())
                pcall(function() Options.EH_MobFarmWeapon:SetValue(H.Config.MobFarmWeaponName) end)
            end
        end})
        left:AddSlider("EH_MobFarmDetectionRange", {
            Text = "Detection radius", Default = H.Config.MobFarmDetectionRange,
            Min = 50, Max = 3000, Rounding = 0, Suffix = " studs",
            Callback = function(v) H.Config.MobFarmDetectionRange = v R.Target = nil end,
        })
        left:AddButton({Text = "Scan / log aggressive candidates", Func = function() M.Candidates(true) end})
        left:AddLabel("Strict target rule: Workspace.Monsters only + live Humanoid named Enemy + CanAttack=true + BaseDamage/AggroRange/AttackRange > 0. Friendly, dialogue NPCs and Training Dummy are rejected.", true)

        right:AddDropdown("EH_MobFarmMoveMode", {
            Text = "Movement", Values = {"Fly", "TP"},
            Default = H.Config.MobFarmMoveMode,
            Multi = false,
            Callback = function(v) if v == "Fly" or v == "TP" then H.Config.MobFarmMoveMode = v end end,
        })
        right:AddSlider("EH_MobFarmDistance", {
            Text = "Preferred range", Default = H.Config.MobFarmDistance,
            Min = 5, Max = 120, Rounding = 0, Suffix = " studs",
            Callback = function(v) H.Config.MobFarmDistance = v end,
        })
        right:AddSlider("EH_MobFarmSafetyMargin", {
            Text = "Extra range beyond mob attack", Default = H.Config.MobFarmSafetyMargin,
            Min = 2, Max = 40, Rounding = 0, Suffix = " studs",
            Callback = function(v) H.Config.MobFarmSafetyMargin = v end,
        })
        right:AddSlider("EH_MobFarmHeight", {
            Text = "Height above mob", Default = H.Config.MobFarmHeight,
            Min = 0, Max = 40, Rounding = 0, Suffix = " studs",
            Callback = function(v) H.Config.MobFarmHeight = v end,
        })
        right:AddSlider("EH_MobFarmFlySpeed", {
            Text = "Fly speed", Default = H.Config.MobFarmFlySpeed,
            Min = 20, Max = 250, Rounding = 0, Suffix = " studs/s",
            Callback = function(v) H.Config.MobFarmFlySpeed = v end,
        })
        right:AddSlider("EH_MobFarmOrbitSpeed", {
            Text = "Orbit speed", Default = H.Config.MobFarmOrbitSpeed,
            Min = 0, Max = 120, Rounding = 0, Suffix = " deg/s",
            Callback = function(v) H.Config.MobFarmOrbitSpeed = v end,
        })
        right:AddSlider("EH_MobFarmShotInterval", {
            Text = "Attack interval", Default = H.Config.MobFarmShotInterval,
            Min = 0.08, Max = 2, Rounding = 2, Suffix = "s",
            Callback = function(v) H.Config.MobFarmShotInterval = v end,
        })
        right:AddToggle("EH_MobFarmLockAim", {
            Text = "Lock aim", Default = H.Config.MobFarmLockAim,
            Callback = function(v) H.Config.MobFarmLockAim = v end,
        })
        right:AddToggle("EH_MobFarmNoclip", {
            Text = "Combat noclip", Default = H.Config.MobFarmNoclip,
            Callback = function(v) H.Config.MobFarmNoclip = v end,
        })
        right:AddLabel("The bot keeps outside each mob's own AttackRange + your safety margin, orbits to avoid standing still, checks line of sight and backs off farther after taking damage. This is safest with a ranged weapon.", true)

        status:AddLabel("EH_MobFarmStatus", {Text = "Status: IDLE", DoesWrap = true})
        status:AddLabel("EH_MobFarmTarget", {Text = "Target: None", DoesWrap = true})
        status:AddLabel("EH_MobFarmHP", {Text = "Target HP: --/--", DoesWrap = true})
        status:AddLabel("EH_MobFarmCandidates", {Text = "Aggressive candidates: 0", DoesWrap = true})
        status:AddLabel("EH_MobFarmKills", {Text = "Observed target deaths: 0", DoesWrap = true})
        status:AddButton({Text = "STOP MOB FARM", Func = function()
            M.Stop()
            if Toggles.EH_MobFarmEnabled then Toggles.EH_MobFarmEnabled:SetValue(false) end
        end})

        task.spawn(function()
            while not H.State.Unloaded do
                pcall(function()
                    if Options.EH_MobFarmStatus then Options.EH_MobFarmStatus:SetText("Status: " .. tostring(H.State.MobFarmStatus)) end
                    if Options.EH_MobFarmTarget then Options.EH_MobFarmTarget:SetText("Target: " .. tostring(H.State.MobFarmTarget)) end
                    if Options.EH_MobFarmHP then Options.EH_MobFarmHP:SetText("Target HP: " .. tostring(H.State.MobFarmHP)) end
                    if Options.EH_MobFarmCandidates then Options.EH_MobFarmCandidates:SetText("Aggressive candidates: " .. tostring(H.State.MobFarmCandidates or 0)) end
                    if Options.EH_MobFarmKills then Options.EH_MobFarmKills:SetText("Observed target deaths: " .. tostring(H.State.MobFarmObservedKills or 0)) end
                end)
                task.wait(0.25)
            end
        end)
    end

    buildUI()

    C.Connect(RunService.Heartbeat, function(dt)
        if H.State.Unloaded or not H.Config.MobFarmEnabled then return end
        local root = C.Root()
        local myHum = C.Humanoid()
        if not root or not myHum or myHum.Health <= 0 then
            H.State.MobFarmStatus = "WAIT CHARACTER"
            return
        end

        if R.LastHealth and myHum.Health < R.LastHealth then
            R.DodgeUntil = tick() + 1.5
            R.OrbitSign = -R.OrbitSign
            H.State.MobFarmStatus = "DAMAGE TAKEN -> EVADING"
        end
        R.LastHealth = myHum.Health

        local target = R.Target
        if target and not targetAlive(target) then
            local hum = enemyHumanoid(target)
            if hum and hum.Health <= 0 and not R.CountedDeaths[target] then
                R.CountedDeaths[target] = true
                H.State.MobFarmObservedKills = (H.State.MobFarmObservedKills or 0) + 1
            end
            R.Target = nil
            target = nil
        end
        if not target then target = acquireTarget() end
        if not target then
            H.State.MobFarmStatus = "NO AGGRESSIVE MOB IN RANGE"
            H.State.MobFarmTarget = "None"
            H.State.MobFarmHP = "--/--"
            return
        end

        local ok, _, meta = M.Classify(target)
        local body = C.NPCAnchor(target)
        local aim = aimPart(target)
        if not ok or not meta or not body or not aim then
            R.Target = nil
            H.State.MobFarmStatus = "TARGET REJECTED / INVALID"
            return
        end

        H.State.MobFarmTarget = target.Name
        H.State.MobFarmHP = string.format("%d/%d", math.max(0, math.floor(meta.Humanoid.Health)), math.max(0, math.floor(meta.Humanoid.MaxHealth)))

        if H.Config.MobFarmNoclip then C.Noclip(true) end
        local destination, safeRange = desiredPosition(root, body, meta.AttackRange, dt)
        local actualDistance = (root.Position - body.Position).Magnitude
        local emergency = actualDistance <= (meta.AttackRange + math.max(2, tonumber(H.Config.MobFarmSafetyMargin) or 10) * 0.65)
        moveTo(root, destination, aim.Position, dt, emergency)

        local cam = workspace.CurrentCamera
        if H.Config.MobFarmLockAim and cam then
            pcall(function() cam.CFrame = CFrame.lookAt(cam.CFrame.Position, aim.Position) end)
        end
        moveMouseTo(aim.Position)
        M.GetWeaponTool(true)

        if not hasLineOfSight(target, aim) then
            R.OrbitAngle = R.OrbitAngle + math.rad(20) * R.OrbitSign
            H.State.MobFarmStatus = "REPOSITIONING FOR LINE OF SIGHT"
            return
        end

        if actualDistance < meta.AttackRange + math.max(2, tonumber(H.Config.MobFarmSafetyMargin) or 10) then
            H.State.MobFarmStatus = string.format("EVADING | %.1f < safe %.1f", actualDistance, safeRange)
            return
        end

        local interval = math.max(0.08, tonumber(H.Config.MobFarmShotInterval) or 0.45)
        if tick() - R.LastShot >= interval then
            R.LastShot = tick()
            H.State.MobFarmStatus = "ATTACKING AGGRESSIVE MOB"
            fire(aim)
        else
            H.State.MobFarmStatus = "ORBITING / AIMING"
        end
    end)

    print("[EndHub] strict aggressive mob farm loaded")
end
