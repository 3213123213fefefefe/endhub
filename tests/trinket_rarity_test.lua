local function item(name, rarity, valid)
    local obj = {Name = name, Valid = valid, Rarity = rarity}
    function obj:GetAttribute(key) if key == 'Rarity' then return self.Rarity end end
    function obj:FindFirstChild() return nil end
    function obj:GetDescendants() return {} end
    return obj
end

tick = function() return 1 end
local group = {AddToggle = function() end, AddDropdown = function() end,
    AddLabel = function() end, AddButton = function() end}
local H = {
    Config = {PickupRarityFilter = true, PickupRarities = {Elite = true}, PickupBlueTomes = true,
        AlwaysPickupEnabled = true, AlwaysPickupLoot = {['Special Compass'] = true}},
    Core = {
        IsTrinketDrop = function(obj) return obj and obj.Valid end,
        NormalizeRarity = function(value) return value end,
        DropsFolder = function() return nil end,
    },
    Farm = {
        Allowed = function(obj) return obj and obj.Valid and obj.Base == true end,
        LootName = function(obj) return obj.Name end,
        GetLootNames = function() return {} end,
        ClearTarget = function() end,
    },
    UI = {Options = {}, Tabs = {Botting = {AddRightGroupbox = function() return group end}}},
}

assert(loadfile('modules/trinket_rarity.lua'))()(H)
local blueTome = item('Enhancement Tome (Stun Protection)', 'Rare', true)
blueTome.Base = false -- The additive option bypasses the independent name filter.
assert(H.Farm.Allowed(blueTome) == true)
local blueItem = item('Aegis Banner', 'Rare', true); blueItem.Base = false
assert(H.Farm.Allowed(blueItem) == false)
local commonTome = item('Enhancement Tome', 'Common', true); commonTome.Base = false
assert(H.Farm.Allowed(commonTome) == false)
local wanted = item('Special Compass', 'Common', true); wanted.Base = false
assert(H.Farm.Allowed(wanted) == true)
local unwanted = item('Ordinary Compass', 'Common', true); unwanted.Base = false
assert(H.Farm.Allowed(unwanted) == false)
local elite = item('Festered Meat', 'Elite', true); elite.Base = true
assert(H.Farm.Allowed(elite) == true)
H.Config.PickupBlueTomes = false
assert(H.Farm.Allowed(blueTome) == false)
H.Config.AlwaysPickupEnabled = false
assert(H.Farm.Allowed(wanted) == false)
print('Trinket rarity blue-tome test: PASS')
