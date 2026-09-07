return function(H)
    H.PlayerTools = {
        Selected = nil,
        Spectating = false,
    }

    local P = H.PlayerTools
    local C = H.Core
    local Players = H.S.Players

    function P.List()
        local out = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= H.S.Player then out[#out + 1] = plr end
        end
        table.sort(out, function(a, b) return string.lower(a.Name) < string.lower(b.Name) end)
        return out
    end

    function P.Names()
        local out = {}
        for _, plr in ipairs(P.List()) do out[#out + 1] = plr.Name end
        return out
    end

    function P.Select(name)
        if type(name) ~= "string" or name == "" then
            P.Selected = nil
            return nil
        end
        local plr = Players:FindFirstChild(name)
        if plr == H.S.Player then plr = nil end
        P.Selected = plr
        return plr
    end

    function P.SelectedRoot()
        return P.Selected and C.Root(P.Selected) or nil
    end

    function P.TeleportSelected()
        local targetRoot = P.SelectedRoot()
        if not targetRoot then return false end
        return C.Teleport(targetRoot.Position + Vector3.new(0, 3, 0), targetRoot.Position)
    end

    function P.SpectateSelected()
        local hum = P.Selected and C.Humanoid(P.Selected)
        local cam = workspace.CurrentCamera
        if not hum or not cam then return false end
        cam.CameraSubject = hum
        P.Spectating = true
        return true
    end

    function P.StopSpectate()
        local cam = workspace.CurrentCamera
        local hum = C.Humanoid()
        if cam and hum then cam.CameraSubject = hum end
        P.Spectating = false
    end

    function P.Info()
        local plr = P.Selected
        if not plr or not plr.Parent then
            return {
                Name = "None",
                Rank = "N/A",
                Distance = nil,
                Health = nil,
                Equipped = "None",
            }
        end
        local hum = C.Humanoid(plr)
        return {
            Name = plr.Name,
            Rank = C.PlayerGrade(plr),
            Distance = C.PlayerDistance(plr),
            Health = hum and hum.Health or nil,
            Equipped = C.EquippedName(plr),
        }
    end

    function P.Reset()
        P.StopSpectate()
        P.Selected = nil
    end

    C.Connect(Players.PlayerRemoving, function(plr)
        if P.Selected == plr then
            P.StopSpectate()
            P.Selected = nil
        end
    end)
end
