return function(H)
    H.Movement = {}
    local M = H.Movement
    local C = H.Core
    local UIS = H.S.UIS

    local keys = {W=false,A=false,S=false,D=false,Space=false,Ctrl=false}

    function M.Reset()
        H.Config.MovementFly = false
        H.Config.MovementNoclip = false
        C.Noclip(false)
        local hum = C.Humanoid()
        if hum then hum.WalkSpeed = 16 end
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
            hum.WalkSpeed = H.Config.WalkSpeed
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
        if keys.Space then dir = dir + Vector3.new(0,1,0) end
        if keys.Ctrl then dir = dir - Vector3.new(0,1,0) end

        if dir.Magnitude > 0 then
            dir = dir.Unit
            root.CFrame = root.CFrame + dir * H.Config.MovementFlySpeed * dt
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end
