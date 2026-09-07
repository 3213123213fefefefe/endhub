return function(H)
    H.Movement = {}
    local M = H.Movement
    local C = H.Core
    local UIS = H.S.UIS

    local keys = {W=false,A=false,S=false,D=false,Space=false,Ctrl=false}

    function M.StopFly()
        H.Config.MovementFly = false
        local root = C.Root()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    function M.ResetCharacter()
        local hum = C.Humanoid()
        if hum then hum.Health = 0 end
    end

    function M.Reset()
        H.Config.MovementFly = false
        H.Config.MovementNoclip = false
        H.Config.Desync = false
        C.Noclip(false)
        local hum = C.Humanoid()
        if hum then
            hum.WalkSpeed = 16
            hum.CameraOffset = Vector3.zero
        end
    end

    C.Connect(UIS.InputBegan, function(input, gp)
        if gp then return end
        local k = input.KeyCode
        if k == Enum.KeyCode.W then keys.W = true
        elseif k == Enum.KeyCode.A then keys.A = true
        elseif k == Enum.KeyCode.S then keys.S = true
        elseif k == Enum.KeyCode.D then keys.D = true
        elseif k == Enum.KeyCode.Space then keys.Space = true
        elseif k == Enum.KeyCode.LeftControl then keys.Ctrl = true end
    end)

    C.Connect(UIS.InputEnded, function(input)
        local k = input.KeyCode
        if k == Enum.KeyCode.W then keys.W = false
        elseif k == Enum.KeyCode.A then keys.A = false
        elseif k == Enum.KeyCode.S then keys.S = false
        elseif k == Enum.KeyCode.D then keys.D = false
        elseif k == Enum.KeyCode.Space then keys.Space = false
        elseif k == Enum.KeyCode.LeftControl then keys.Ctrl = false end
    end)

    C.Connect(H.S.RunService.RenderStepped, function(dt)
        if H.State.Unloaded then return end

        local hum = C.Humanoid()
        if hum and not H.Config.MovementFly then
            hum.WalkSpeed = math.max(0, H.Config.WalkSpeed * H.Config.SpeedMultiplier)
        end

        if hum then
            if H.Config.Desync and not H.State.Running and not H.Config.AutoSell then
                local wave = math.sin(tick() * math.pi * 2 * H.Config.DesyncRate)
                hum.CameraOffset = Vector3.new(wave * H.Config.DesyncOffset, 0, 0)
            elseif hum.CameraOffset ~= Vector3.zero then
                hum.CameraOffset = Vector3.zero
            end
        end

        if H.Config.MovementNoclip or H.Config.MovementFly then
            C.Noclip(true)
        elseif not H.Config.BotNoclip or not H.State.Running then
            C.Noclip(false)
        end

        if not H.Config.MovementFly then return end
        local root = C.Root()
        local cam = workspace.CurrentCamera
        if not root or not cam then return end

        local dir = Vector3.zero
        local cf = cam.CFrame
        if keys.W then dir = dir + cf.LookVector end
        if keys.S then dir = dir - cf.LookVector end
        if keys.D then dir = dir + cf.RightVector end
        if keys.A then dir = dir - cf.RightVector end
        if keys.Space then dir = dir + Vector3.yAxis end
        if keys.Ctrl then dir = dir - Vector3.yAxis end

        local newPos = root.Position
        if dir.Magnitude > 0 then
            newPos = newPos + dir.Unit * H.Config.MovementFlySpeed * dt
        end
        root.CFrame = CFrame.lookAt(newPos, newPos + cam.CFrame.LookVector)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end
