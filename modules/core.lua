return function(H)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local VIM = game:GetService("VirtualInputManager")
    local Lighting = game:GetService("Lighting")
    local RS = game:GetService("ReplicatedStorage")

    H.S = {
        Players = Players,
        RunService = RunService,
        UIS = UIS,
        VIM = VIM,
        Lighting = Lighting,
        RS = RS,
        Player = Players.LocalPlayer,
    }

    H.Core = {}
    local C = H.Core

    function C.Connect(signal, callback)
        local con = signal:Connect(callback)
        H.Connections[#H.Connections + 1] = con
        return con
    end

    function C.Character()
        return H.S.Player.Character
    end

    function C.Root()
        local ch = C.Character()
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    function C.Humanoid()
        local ch = C.Character()
        return ch and ch:FindFirstChildWhichIsA("Humanoid") or nil
    end

    function C.NPCFolder()
        return workspace:FindFirstChild("NPCs")
    end

    function C.DropsFolder()
        return workspace:FindFirstChild("Drops")
    end

    function C.NPCAnchor(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("Head")
            or model:FindFirstChild("WispHead")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    function C.DropPart(model)
        if not model or not model.Parent then return nil end
        return model:FindFirstChild("Handle")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    function C.IsTrinketDrop(model)
        return model
            and model:IsA("Model")
            and model:FindFirstChild("AtTrinketSpawn") ~= nil
            and model:FindFirstChild("IsInteractable") ~= nil
            and C.DropPart(model) ~= nil
    end

    function C.PressKey(code)
        if keypress and keyrelease then
            task.spawn(function()
                pcall(function()
                    keypress(code)
                    task.wait(0.05)
                    keyrelease(code)
                end)
            end)
            return
        end

        local map = {
            [0x45] = Enum.KeyCode.E,
            [0x31] = Enum.KeyCode.One,
        }
        local key = map[code]
        if not key then return end
        task.spawn(function()
            pcall(function()
                VIM:SendKeyEvent(true, key, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, key, false, game)
            end)
        end)
    end

    function C.ReadCapacity()
        local pg = H.S.Player:FindFirstChild("PlayerGui")
        if not pg then return nil, nil end

        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local t = tostring(obj.Text or "")
                local a, b = string.match(t, "[Cc]apacity%s*:%s*(%d+)%s*/%s*(%d+)")
                if a and b then
                    a, b = tonumber(a), tonumber(b)
                    if a and b and b > 0 then
                        H.State.InventoryCurrent = a
                        H.State.InventoryMax = b
                        H.State.InventoryPercent = (a / b) * 100
                        return a, b
                    end
                end
            end
        end
        return nil, nil
    end

    function C.FindClement()
        local folder = C.NPCFolder()
        if not folder then return nil end

        local exact = folder:FindFirstChild("Clement, Merchant")
        if exact and exact:IsA("Model") then
            local p = C.NPCAnchor(exact)
            if p then
                getgenv().ENDHUB_SELLER_POSITIONS.Clement = {p.Position.X, p.Position.Y, p.Position.Z}
            end
            return exact
        end

        for _, npc in ipairs(folder:GetChildren()) do
            if npc:IsA("Model") and string.find(string.lower(npc.Name), "merchant", 1, true) then
                local p = C.NPCAnchor(npc)
                if p then
                    getgenv().ENDHUB_SELLER_POSITIONS.Clement = {p.Position.X, p.Position.Y, p.Position.Z}
                end
                return npc
            end
        end
        return nil
    end

    function C.GetSavedSeller()
        local v = getgenv().ENDHUB_SELLER_POSITIONS.Clement
        if type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) then
            return Vector3.new(v[1], v[2], v[3])
        end
        return nil
    end

    function C.Teleport(pos, lookAt)
        local root = C.Root()
        if not root then return false end
        if lookAt then
            root.CFrame = CFrame.new(pos, lookAt)
        else
            root.CFrame = CFrame.new(pos)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    H.OriginalCollision = {}
    function C.Noclip(active)
        local ch = C.Character()
        if not ch then return end
        if active then
            for _, p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") then
                    if H.OriginalCollision[p] == nil then
                        H.OriginalCollision[p] = p.CanCollide
                    end
                    p.CanCollide = false
                end
            end
        else
            for p, old in pairs(H.OriginalCollision) do
                if p and p.Parent then pcall(function() p.CanCollide = old end) end
            end
            table.clear(H.OriginalCollision)
        end
    end

    H.SellCategoryFrames = {
        WeaponFrame = "Weapon",
        ItemsFrame = "Item",
        TrinketsFrame = "Trinket",
        AccessoryFrame = "Accessory",
        PotionsFrame = "Potion",
        OutfitFrame = "Outfit",
        TomesFrame = "Tome",
        SummonFrame = "Summon",
        GemsFrame = "Gem",
    }

    function C.NormalizeRarity(v)
        v = tostring(v or "Unknown")
        v = string.gsub(v, "^%s+", "")
        v = string.gsub(v, "%s+$", "")
        if v == "" then v = "Unknown" end
        return string.upper(string.sub(v, 1, 1)) .. string.lower(string.sub(v, 2))
    end

    function C.ToolRarity(tool)
        local r = tool and tool:FindFirstChild("Rarity")
        if r and r:IsA("StringValue") then
            return C.NormalizeRarity(r.Value)
        end
        return "Unknown"
    end
end
