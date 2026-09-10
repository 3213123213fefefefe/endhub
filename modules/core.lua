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

    -- Executor workspaces can be shared by every Roblox process. Never use
    -- one writable profile for different accounts/maps. The optional profile
    -- suffix also supports separate configurations for the same account.
    local priorProfile
    pcall(function() priorProfile = game:GetService("TeleportService"):GetTeleportSetting("EndHubProfile") end)
    local profile = tostring(ENV.ENDHUB_PROFILE or priorProfile or "default"):gsub("[^%w_-]", "_"):sub(1, 48)
    pcall(function() game:GetService("TeleportService"):SetTeleportSetting("EndHubProfile", profile) end)
    local directory = "EndHub/accounts/" .. tostring(H.S.Player.UserId)
        .. "/" .. tostring(game.PlaceId) .. "/" .. profile
    H.Persistence = {
        Dir = directory,
        SellerFile = directory .. "/seller_positions.json",
        KeybindFile = directory .. "/keybinds.json",
        ConfigFile = directory .. "/config.json",
        PositionsFile = directory .. "/bot_positions.json",
        VisitedFile = directory .. "/serverhop_visited.json",
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

    local focused = true
    if UIS.WindowFocused then C.Connect(UIS.WindowFocused, function() focused = true end) end
    if UIS.WindowFocusReleased then C.Connect(UIS.WindowFocusReleased, function() focused = false end) end
    function C.InputFocused()
        local probe = isrbxactive or iswindowactive
        if type(probe) == "function" then
            local ok, active = pcall(probe)
            if ok then return active == true end
        end
        return focused
    end

    local keysDown = {}
    function C.PressKey(code)
        if H.State.Unloaded or not C.InputFocused() or keysDown[code] then return false end
        local map = {[0x45] = Enum.KeyCode.E, [0x31] = Enum.KeyCode.One}
        local key = map[code]
        if not key then return false end
        keysDown[code] = true
        task.spawn(function()
            if not H.State.Unloaded and C.InputFocused() then
                pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
                task.wait(0.05)
                -- Always release a key we pressed, even if focus changes.
                pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
            end
            keysDown[code] = nil
        end)
        return true
    end

    local function ensureDir()
        if not isfolder or not makefolder then return false end
        local prefix = ""
        for part in H.Persistence.Dir:gmatch("[^/]+") do
            prefix = prefix == "" and part or prefix .. "/" .. part
            local ok, exists = pcall(isfolder, prefix)
            if not ok then return false end
            if not exists then
                local made = pcall(makefolder, prefix)
                if not made then
                    local checked, nowExists = pcall(isfolder, prefix)
                    if not checked or not nowExists then return false end
                end
            end
        end
        return true
    end

    local function fallbackPath(path) return tostring(path):gsub("[^%w_.-]", "_") end
    local function readRaw(path)
        if not readfile then return nil end
        if isfile then
            local okFile, exists = pcall(isfile, path)
            if not okFile or not exists then return nil end
        end
        local okRead, raw = pcall(readfile, path)
        return okRead and type(raw) == "string" and raw or nil
    end
    function C.ReadJson(path)
        local raw, used = readRaw(path), path
        if not raw then used = fallbackPath(path) raw = readRaw(used) end
        if not raw then return nil end
        local okJson, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if okJson and type(decoded) == "table" then H.State.PersistencePath = used return decoded end
        return nil
    end

    function C.WriteJson(path, value)
        if not writefile then return false end
        local okJson, raw = pcall(HttpService.JSONEncode, HttpService, value)
        if not okJson then return false end
        ensureDir()
        local ok = pcall(writefile, path, raw)
        if ok and (not readfile or readRaw(path) ~= nil) then H.State.PersistencePath = path return true end
        local flat = fallbackPath(path)
        ok = pcall(writefile, flat, raw)
        if ok then H.State.PersistencePath = flat return true end
        return false
    end

    function C.ReadProfile(path, legacyName)
        local own = C.ReadJson(path)
        if own then return own end
        local legacy = legacyName and C.ReadJson("EndHub/" .. legacyName)
        if legacy then C.WriteJson(path, legacy) end
        return legacy
    end

    ENV.ENDHUB_SELLER_POSITIONS = ENV.ENDHUB_SELLER_POSITIONS or {}
    local savedSellerDisk = C.ReadProfile(H.Persistence.SellerFile, "seller_positions.json")
    if type(savedSellerDisk) == "table" then
        for k, v in pairs(savedSellerDisk) do
            if ENV.ENDHUB_SELLER_POSITIONS[k] == nil then ENV.ENDHUB_SELLER_POSITIONS[k] = v end
        end
    end

    function C.SaveSellerPosition(pos)
        if typeof(pos) ~= "Vector3" then return end
        local old = ENV.ENDHUB_SELLER_POSITIONS["Clement, Merchant"] or ENV.ENDHUB_SELLER_POSITIONS.Clement
        local changed = true
        if type(old) == "table" and tonumber(old[1]) and tonumber(old[2]) and tonumber(old[3]) then
            changed = math.abs(tonumber(old[1]) - pos.X) > 0.05
                or math.abs(tonumber(old[2]) - pos.Y) > 0.05
                or math.abs(tonumber(old[3]) - pos.Z) > 0.05
        end
        local data = {pos.X, pos.Y, pos.Z}
        ENV.ENDHUB_SELLER_POSITIONS["Clement, Merchant"] = data
        ENV.ENDHUB_SELLER_POSITIONS.Clement = data
        if changed then C.WriteJson(H.Persistence.SellerFile, ENV.ENDHUB_SELLER_POSITIONS) end
    end

    function C.ClearSavedSeller()
        ENV.ENDHUB_SELLER_POSITIONS["Clement, Merchant"] = nil
        ENV.ENDHUB_SELLER_POSITIONS.Clement = nil
        C.WriteJson(H.Persistence.SellerFile, ENV.ENDHUB_SELLER_POSITIONS)
    end

    function C.GetSavedSeller()
        -- Captured Clement coordinates, keyed by map PlaceId.
        local embeddedByPlace = {
            ["125503525638054"] = {242.51593, 188.5, 1.00323868},
        }
        local key = tostring(game.PlaceId)
        local fixed = embeddedByPlace[key]
            or (H.Config.FixedSellerByPlace and H.Config.FixedSellerByPlace[key])
        if type(fixed) == "table" and tonumber(fixed[1]) and tonumber(fixed[2]) and tonumber(fixed[3]) then
            return Vector3.new(tonumber(fixed[1]), tonumber(fixed[2]), tonumber(fixed[3]))
        end
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
            if npc:IsA("Model") and npc.Name == "Clement" then
                local p = C.NPCAnchor(npc)
                if p then C.SaveSellerPosition(p.Position) end
                return npc
            end
        end
        return nil
    end

    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local savedKeysDisk = C.ReadProfile(H.Persistence.KeybindFile, "keybinds.json")
    if type(savedKeysDisk) == "table" then
        for k, v in pairs(savedKeysDisk) do
            ENV.ENDHUB_KEYBINDS[k] = v
        end
    end

    function C.SaveKeybinds()
        local ok = C.WriteJson(H.Persistence.KeybindFile, ENV.ENDHUB_KEYBINDS)
        H.State.PersistenceStatus = ok and "KEYBINDS SAVED" or "KEYBIND SAVE FAILED"
        return ok
    end

    local capacityLabel, capacityScanAt = nil, -math.huge
    function C.ReadCapacity()
        local pg = H.S.Player:FindFirstChild("PlayerGui")
        if not pg then return nil, nil end

        if capacityLabel and capacityLabel.Parent and capacityLabel:IsDescendantOf(pg) then
            local a, b = tostring(capacityLabel.Text):match("(%d+)%s*/%s*(%d+)")
            a, b = tonumber(a), tonumber(b)
            if a and b and b > 0 then
                H.State.InventoryCurrent, H.State.InventoryMax, H.State.InventoryPercent = a, b, a / b * 100
                return a, b
            end
        end
        if tick() - capacityScanAt < 1 then return nil, nil end
        capacityScanAt = tick()
        capacityLabel = nil
        local fallbackA, fallbackB, fallbackLabel
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
                        if fa and fb then fallbackA, fallbackB, fallbackLabel = fa, fb, obj end
                    end
                end
                if a and b then
                    a, b = tonumber(a), tonumber(b)
                    if a and b and b > 0 then
                        capacityLabel = obj
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
                capacityLabel = fallbackLabel
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

