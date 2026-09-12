return function(H)
    H.Movement = {}
    local M = H.Movement
    local C = H.Core
    local UIS = H.S.UIS
    local TweenService = game:GetService("TweenService")

    local keys = {W=false, A=false, S=false, D=false, Space=false, Ctrl=false}
    local activeTween = nil
    local tweenDirection = nil
    local tweenRoot = nil
    H.Config.SpeedModifierEnabled = false

    local function cancelTween()
        if activeTween then
            pcall(function() activeTween:Cancel() end)
        end
        activeTween = nil
        tweenDirection = nil
        tweenRoot = nil
    end

    local function inputDirection(cam)
        local dir = Vector3.zero
        local cf = cam.CFrame
        if keys.W then dir = dir + cf.LookVector end
        if keys.S then dir = dir - cf.LookVector end
        if keys.D then dir = dir + cf.RightVector end
        if keys.A then dir = dir - cf.RightVector end
        if keys.Space then dir = dir + Vector3.yAxis end
        if keys.Ctrl then dir = dir - Vector3.yAxis end
        return dir
    end

    function M.SetSpeedModifier(enabled)
        H.Config.SpeedModifierEnabled = enabled and true or false
        local hum = C.Humanoid()
        if hum and not H.Config.MovementFly and not H.Config.MovementFlyTween then
            local mult = H.Config.SpeedModifierEnabled and H.Config.SpeedMultiplier or 1
            hum.WalkSpeed = math.max(0, (H.Config.WalkSpeed or 16) * mult)
        end
    end

    function M.SetFly(enabled)
        H.Config.MovementFly = enabled and true or false
        if enabled then
            H.Config.MovementFlyTween = false
            cancelTween()
        end
    end

    function M.SetFlyTween(enabled)
        H.Config.MovementFlyTween = enabled and true or false
        if enabled then
            H.Config.MovementFly = false
        else
            cancelTween()
        end
    end

    function M.StopFly()
        H.Config.MovementFly = false
        H.Config.MovementFlyTween = false
        cancelTween()
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
        H.Config.MovementFlyTween = false
        H.Config.MovementNoclip = false
        H.Config.SpeedModifierEnabled = false
        cancelTween()
        C.Noclip(false)
        local hum = C.Humanoid()
        if hum then hum.WalkSpeed = H.Config.WalkSpeed or 16 end
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
        if hum and not H.Config.MovementFly and not H.Config.MovementFlyTween then
            local mult = H.Config.SpeedModifierEnabled and H.Config.SpeedMultiplier or 1
            hum.WalkSpeed = math.max(0, (H.Config.WalkSpeed or 16) * mult)
        end

        if H.Config.MovementNoclip or H.Config.MovementFly or H.Config.MovementFlyTween then
            C.Noclip(true)
        elseif not H.Config.BotNoclip or not H.State.Running then
            C.Noclip(false)
        end

        local root = C.Root()
        local cam = workspace.CurrentCamera
        if not root or not cam then
            cancelTween()
            return
        end

        if H.Config.MovementFlyTween then
            local dir = inputDirection(cam)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            if dir.Magnitude <= 0 then
                cancelTween()
                return
            end

            dir = dir.Unit
            local shouldRestart = false
            if not activeTween or tweenRoot ~= root then
                shouldRestart = true
            elseif activeTween.PlaybackState ~= Enum.PlaybackState.Playing then
                shouldRestart = true
            elseif not tweenDirection or tweenDirection:Dot(dir) < 0.985 then
                shouldRestart = true
            end

            if shouldRestart then
                cancelTween()
                local segment = math.max(2, H.Config.MovementFlyTweenSegmentLength or 16)
                local speed = math.max(1, H.Config.MovementFlyTweenSpeed or 90)
                local goalPos = root.Position + dir * segment
                local look = cam.CFrame.LookVector
                local goal = CFrame.lookAt(goalPos, goalPos + look)
                activeTween = TweenService:Create(
                    root,
                    TweenInfo.new(segment / speed, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
                    {CFrame = goal}
                )
                tweenDirection = dir
                tweenRoot = root
                activeTween:Play()
            end
            return
        end

        if activeTween then cancelTween() end
        if not H.Config.MovementFly then return end

        local dir = inputDirection(cam)
        local pos = root.Position
        if dir.Magnitude > 0 then
            pos = pos + dir.Unit * (H.Config.MovementFlySpeed or 120) * dt
        end
        root.CFrame = CFrame.lookAt(pos, pos + cam.CFrame.LookVector)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end
