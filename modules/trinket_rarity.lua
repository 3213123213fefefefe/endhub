return function(H)
    local C, F = H.Core, H.Farm
    assert(C and F and H.UI and H.UI.Tabs, 'EndHub: modulos necessarios indisponiveis')
    local cfg = H.Config
    local defaults = {'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Exotic', 'Elite', 'Unknown'}
    local function allRarities()
        local out = {}
        for _, rarity in ipairs(defaults) do out[rarity] = true end
        return out
    end
    cfg.TrinketESPRarities = type(cfg.TrinketESPRarities) == 'table' and cfg.TrinketESPRarities or allRarities()
    cfg.PickupRarities = type(cfg.PickupRarities) == 'table' and cfg.PickupRarities or allRarities()
    cfg.PickupRarityFilter = cfg.PickupRarityFilter == true
    cfg.TrinketESP = cfg.TrinketESP == true
    cfg.TrinketESPDistance = tonumber(cfg.TrinketESPDistance) or 2000

    local function metadata(obj)
        local value = obj:GetAttribute('Rarity')
        if type(value) == 'string' and value:match('%S') then return C.NormalizeRarity(value) end
        local child = obj:FindFirstChild('Rarity')
        if child and child:IsA('StringValue') and child.Value:match('%S') then return C.NormalizeRarity(child.Value) end
        return nil
    end
    local function scanRarity(obj)
        local direct = metadata(obj)
        if direct then return direct end
        local found
        for _, child in ipairs(obj:GetDescendants()) do
            local value = metadata(child)
            if child.Name == 'Rarity' and child:IsA('StringValue') and child.Value:match('%S') then
                value = C.NormalizeRarity(child.Value)
            end
            if value then
                if found and found ~= value then return 'Unknown' end
                found = value
            end
        end
        return found or 'Unknown'
    end
    local cache = setmetatable({}, {__mode = 'k'})
    local function rarityOf(obj)
        if not obj then return 'Unknown' end
        local old = cache[obj]
        if old and tick() - old.At < 0.5 then return old.Value end
        local value = scanRarity(obj)
        cache[obj] = {Value = value, At = tick()}
        return value
    end
    H.TrinketRarity = {Read = rarityOf}

    local previousAllowed = F.Allowed
    function F.Allowed(obj)
        if not previousAllowed(obj) then return false end
        return not cfg.PickupRarityFilter or cfg.PickupRarities[rarityOf(obj)] == true
    end

    local function selection(value)
        local out = {}
        if type(value) == 'table' then
            for key, enabled in pairs(value) do if enabled == true then out[tostring(key)] = true end end
        end
        return out
    end
    local function rarityChoices()
        local values, seen = {}, {}
        local function add(value) if not seen[value] then seen[value] = true values[#values + 1] = value end end
        for _, value in ipairs(defaults) do add(value) end
        for value in pairs(cfg.TrinketESPRarities) do add(value) end
        for value in pairs(cfg.PickupRarities) do add(value) end
        local folder = C.DropsFolder()
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do if C.IsTrinketDrop(obj) then add(rarityOf(obj)) end end
        end
        return values
    end

    local initialPickup = selection(cfg.PickupRarities)
    local pickupGroup = H.UI.Tabs.Botting:AddRightGroupbox('Pickup Rarity')
    pickupGroup:AddToggle('EH_PickupRarityFilter', {
        Text = 'Only pick selected rarities', Default = cfg.PickupRarityFilter,
        Callback = function(value) cfg.PickupRarityFilter = value F.ClearTarget() end,
    })
    pickupGroup:AddDropdown('EH_PickupRarities', {
        Text = 'Rarities to pick', Values = rarityChoices(), Multi = true, Searchable = true,
        Callback = function(value) cfg.PickupRarities = selection(value) F.ClearTarget() end,
    })
    cfg.PickupRarities = initialPickup

    local options = H.UI.Options
    local function refresh()
        local values = rarityChoices()
        for _, item in ipairs({{'EH_TrinketESPRarities', 'TrinketESPRarities'}, {'EH_PickupRarities', 'PickupRarities'}}) do
            local option = options[item[1]]
            local saved = selection(cfg[item[2]])
            if option then option:SetValues(values) option:SetValue(saved) end
        end
    end
    local function diagnose()
        refresh()
        local folder = C.DropsFolder()
        local count = 0
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if C.IsTrinketDrop(obj) then
                    count = count + 1
                    print('[EndHub Rarity] ' .. F.LootName(obj) .. ' | rarity=' .. rarityOf(obj)
                        .. ' | pickup=' .. tostring(F.Allowed(obj)))
                end
            end
        end
        print('[EndHub Rarity] drops=' .. count)
    end
    pickupGroup:AddButton({Text = 'Refresh rarities / log drops', Func = diagnose})
    refresh()

    print('[EndHub] pickup rarity filter loaded')
end
