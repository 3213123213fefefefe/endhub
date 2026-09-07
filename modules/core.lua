return function(H)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local VIM = game:GetService("VirtualInputManager")
    local Lighting = game:GetService("Lighting")
    local RS = game:GetService("ReplicatedStorage")
    local HttpService = game:GetService("HttpService")

    H.S = {
        Players = Players,
        RunService = RunService,
        UIS = UIS,
        VIM = VIM,
        Lighting = Lighting,
        RS = RS,
        HttpService = HttpService,
        Player = Players.LocalPlayer,
    }

    H.Core = {}
    local C = H.Core
    local ENV = getgenv()

    H.Persistence = {
        Dir = "EndHub",
        SellerFile = "EndHub/seller_positions.json",
        KeybindFile = "EndHub/keybinds.json",
    }

    function C.Connect(signal, callback)
        local con = signal:Connect(callback)
        H.Connections[#H.Connections + 1] = con
        return con
    end

    function C.Character(plr)
        plr = plr or H.S.Player
        return plr and plr.Character or nil
    end

    function C.Root(plr)
        local ch = C.Character(plr)
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    function C.Humanoid(plr)
        local ch = C.Character(plr)
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

    local function ensureDir()
        if not isfolder or not makefolder then return false end
        local ok, exists = pcall(isfolder, H.Persistence.Dir)
        if ok and not exists then
            pcall(makefolder, H.Persistence.Dir)
        end
        return true
    end

    function C.ReadJson(path)
        if not readfile or not isfile then return nil end
        local okFile, exists = pcall(isfile, path)
        if not okFile or not exists then return nil end
        local okRead, raw = pcall(readfile, path)
        if not okRead or type(raw) ~= "string" then return nil end
        local okJson, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if okJson and type(decoded) == "table" then return decoded end
        return nil
    end

    function C.WriteJson(path, value)
        if not writefile then return false end
        ensureDir()
        local okJson, raw = pcall(HttpService.JSONEncode, HttpService, value)
        if not okJson then return false end
        return pcall(writefile, path, raw)
    end

    ENV.ENDHUB_SELLER_POSITIONS = ENV.ENDHUB_SELLER_POSITIONS or {}
    local savedSellerDisk = C.ReadJson(H.Persistence.SellerFile)
    if type(savedSellerDisk) == "table" then
        for k, v in pairs(savedSellerDisk) do
            if ENV.ENDHUB_SELLER_POSITIONS[k] == nil then
                ENV.ENDHUB_SELLER_POSITIONS[k] = v
            end
        end
    end

    function C.SaveSellerPosition(pos)
        if typeof(pos) ~= "Vector3" then return end
        local data = {pos.X, pos.Y, pos.Z}
        ENV.ENDHUB_SELLER_POSITIONS["Clement, Merchant"] = data
        ENV.ENDHUB_SELLER_POSITIONS.Clement = data
        C.WriteJson(H.Persistence.SellerFile, ENV.ENDHUB_SELLER_POSITIONS)
    end

    function C.ClearSavedSeller()
        ENV.ENDHUB_SELLER_POSITIONS["Clement, Merchant"] = nil
        ENV.ENDHUB_SELLER_POSITIONS.Clement = nil
        C.WriteJson(H.Persistence.SellerFile, ENV.ENDHUB_SELLER_POSITIONS)
    end

    function C.GetSavedSeller()
        local t = ENV.ENDHUB_SELLER_POSITIONS
        local v = t["Clement, Merchant"] or t.Clement
        if type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) then
            return Vector3.new(tonumber(v[1]), tonumber(v[2]), tonumber(v[3]))
        end
        return nil
    end

    function C.FindClement()
        local folder = C.NPCFolder()
        if not folder then return nil end

        local exact = folder:FindFirstChild("Clement, Merchant")
        if exact and exact:IsA("Model") then
            local p = C.NPCAnchor(exact)
            if p then C.SaveSellerPosition(p.Position) end
            return exact
        end

        for _, npc in ipairs(folder:GetChildren()) do
            if npc:IsA("Model") and string.find(string.lower(npc.Name), "merchant", 1, true) then
                local p = C.NPCAnchor(npc)
                if p then C.SaveSellerPosition(p.Position) end
                return npc
            end
        end
        return nil
    end

    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local savedKeysDisk = C.ReadJson(H.Persistence.KeybindFile)
    if type(savedKeysDisk) == "table" then
        for k, v in pairs(savedKeysDisk) do
            if ENV.ENDHUB_KEYBINDS[k] == nil then ENV.ENDHUB_KEYBINDS[k] = v end
        end
    end

    function C.SaveKeybinds()
        C.WriteJson(H.Persistence.KeybindFile, ENV.ENDHUB_KEYBINDS)
    end

    function C.ReadCapacity()
        local pg = H.S.Player:FindFirstChild("PlayerGui")
        if not pg then return nil, nil end

        local fallbackA, fallbackB
        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local text = tostring(obj.Text or "")
                local a, b = string.match(text, "[Cc]apacity%s*:?%s*(%d+)%s*/%s*(%d+)")
                if not a and string.find(string.lower(obj.Name), "capacity", 1, true) then
                    a, b = string.match(text, "(%d+)%s*/%s*(%d+)")
                end
                if not a then
                    local node = obj.Parent
                    local insideInventory = false
                    while node do
                        if string.find(string.lower(node.Name), "inventory", 1, true) then
                            insideInventory = true
                            break
                        end
                        node = node.Parent
                    end
                    if insideInventory then
                        local fa, fb = string.match(text, "^%s*(%d+)%s*/%s*(%d+)%s*$")
                        if fa and fb then fallbackA, fallbackB = fa, fb end
                    end
                end
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

        if fallbackA and fallbackB then
            local a, b = tonumber(fallbackA), tonumber(fallbackB)
            if a and b and b > 0 then
                H.State.InventoryCurrent = a
                H.State.InventoryMax = b
                H.State.InventoryPercent = (a / b) * 100
                return a, b
            end
        end
        return nil, nil
    end

    function C.Teleport(pos, lookAt)
        local root = C.Root()
        if not root then return false end
        if lookAt then root.CFrame = CFrame.new(pos, lookAt) else root.CFrame = CFrame.new(pos) end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    H.OriginalCollision = H.OriginalCollision or {}
    function C.Noclip(active)
        local ch = C.Character()
        if not ch then return end
        if active then
            for _, p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") then
                    if H.OriginalCollision[p] == nil then H.OriginalCollision[p] = p.CanCollide end
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
        if r and r:IsA("StringValue") then return C.NormalizeRarity(r.Value) end
        return "Unknown"
    end

    function C.PlayerDistance(plr)
        local a, b = C.Root(), C.Root(plr)
        if not a or not b then return math.huge end
        return (a.Position - b.Position).Magnitude
    end

    function C.PlayerGrade(plr)
        if not plr then return "N/A" end
        for _, attr in ipairs({"Rank", "Grade", "Class", "Title"}) do
            local ok, value = pcall(function() return plr:GetAttribute(attr) end)
            if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
        end
        local leaderstats = plr:FindFirstChild("leaderstats")
        if leaderstats then
            for _, name in ipairs({"Rank", "Grade", "Class", "Title"}) do
                local v = leaderstats:FindFirstChild(name)
                if v and v:IsA("ValueBase") then return tostring(v.Value) end
            end
        end
        for _, name in ipairs({"Rank", "Grade", "Class", "Title"}) do
            local v = plr:FindFirstChild(name)
            if v and v:IsA("ValueBase") then return tostring(v.Value) end
        end
        return "N/A"
    end

    function C.EquippedName(plr)
        local ch = C.Character(plr)
        local tool = ch and ch:FindFirstChildWhichIsA("Tool")
        return tool and tool.Name or "None"
    end
end
