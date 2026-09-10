local ENV = getgenv()

if ENV.ENDHUB and ENV.ENDHUB.Unload then
    pcall(function() ENV.ENDHUB:Unload() end)
end

local H = {
    JobId = tostring(game.JobId),
    Repo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/",
    Connections = {},
    Drawings = {},
    Modules = {},
    Config = {
        PickupDistance = 7,
        TargetHeight = 3,
        PickupInterval = 0.30,
        TargetTimeout = 15,
        AutoPickup = true,
        BotNoclip = true,
        FarmMoveMode = "Tween",
        FarmTweenSpeed = 85,
        FarmTweenSegmentLength = 20,
        FarmTweenPauseSeconds = 0.2,
        FarmTweenGroundPauses = true,
        FarmFlySpeed = 85,
        LootFilterEnabled = false,
        LootWhitelist = {},

        AutoSell = false,
        AutoFarmSell = false,
        SellAtPercent = 100,
        ResumeAtPercent = 90,
        SellInterval = 0.80,
        SellerInteractInterval = 0.65,
        SellerInteractDistance = 7,
        SellByRarity = {},

        MovementFly = false,
        MovementFlySpeed = 120,
        MovementNoclip = false,
        WalkSpeed = 16,
        SpeedMultiplier = 1,
        SpeedModifierEnabled = false,

        BossBotEnabled = false,
        BossTargetName = "AUTO: Highest MaxHealth",
        BossWeaponName = "Use Equipped",
        BossDistance = 55,
        BossDepth = 18,
        BossShotInterval = 0.45,
        BossAutoShoot = true,
        BossLockAim = true,
        BossNoclip = true,
        BossAimPart = "Head",

        MobFarmEnabled = false,
        MobFarmWeaponName = "Use Equipped",
        MobFarmMoveMode = "Fly",
        MobFarmDetectionRange = 600,
        MobFarmDistance = 32,
        MobFarmSafetyMargin = 10,
        MobFarmHeight = 8,
        MobFarmFlySpeed = 95,
        MobFarmShotInterval = 0.45,
        MobFarmOrbitSpeed = 35,
        MobFarmLockAim = true,
        MobFarmNoclip = true,

        NoFog = false,
        Fullbright = false,
        FullbrightBrightness = 4,
        FullbrightAmbient = 0.75,
        FullbrightClockTime = 14,
        NPCESP = false,
        PlayerESP = false,
        ESPShowRank = true,
        ESPShowDistance = true,
        ESPShowEquipped = false,
        ESPShowPrestige = true,
        ESPShowMaxHealth = true,
        ESPShowSanity = true,
    },
    State = {
        Ready = false,
        Running = false,
        Unloaded = false,
        Status = "IDLE",
        SellStatus = "IDLE",
        PersistenceStatus = "INIT",
        CurrentTarget = nil,
        TargetStarted = 0,
        TargetDistance = 0,
        LastPickup = 0,
        Collected = 0,
        Detected = 0,
        StartedAt = 0,
        InventoryCurrent = 0,
        InventoryMax = 0,
        InventoryPercent = 0,
        FarmSellPhase = "FARM",

        BossStatus = "IDLE",
        BossTarget = "None",
        BossHP = "--/--",
        BossWeapon = "None",
        BossDistance = 0,

        MobFarmStatus = "IDLE",
        MobFarmTarget = "None",
        MobFarmHP = "--/--",
        MobFarmCandidates = 0,
        MobFarmObservedKills = 0,
    }
}

ENV.ENDHUB = H
ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
ENV.ENDHUB_SELLER_POSITIONS = ENV.ENDHUB_SELLER_POSITIONS or {}

local function loadModule(path)
    local src = game:HttpGet(H.Repo .. path .. "?v=" .. tostring(os.clock()) .. "-" .. tostring(math.random()))
    local fn, err = loadstring(src)
    if not fn then error("[EndHub] compile failed " .. path .. ": " .. tostring(err)) end
    local init = fn()
    if type(init) ~= "function" then error("[EndHub] invalid module " .. path) end
    init(H)
end

local order = {
    "modules/core.lua",
    "modules/persistence.lua",
    "modules/farm_movement.lua",
    "modules/farm.lua",
    "modules/sell.lua",
    "modules/ui.lua",
    "modules/menu_key_fix.lua",
    "modules/farm_ui.lua",
    "modules/ui_compat.lua",
    "modules/trinket_sell_fix.lua",
    "modules/trinket_rarity.lua",
    "modules/trinket_route.lua",
    "modules/features.lua",
    "modules/extras.lua",
}

function H:Unload()
    if self.State.Unloaded then return end
    if self.Features then self.Features.Close() end

    if self.PersistenceManager and self.PersistenceManager.SaveAll then
        pcall(function() self.PersistenceManager.SaveAll(true) end)
    end

    self.State.Unloaded = true
    self.State.Running = false
    self.Config.AutoSell = false
    self.Config.AutoFarmSell = false
    self.Config.SpeedModifierEnabled = false
    self.Config.BossBotEnabled = false
    self.Config.MobFarmEnabled = false

    if self.Farm and self.Farm.Stop then pcall(self.Farm.Stop) end
    if self.Sell and self.Sell.Stop then pcall(self.Sell.Stop) end
    if self.Boss and self.Boss.Stop then pcall(self.Boss.Stop) end
    if self.MobFarm and self.MobFarm.Stop then pcall(self.MobFarm.Stop) end
    if self.PlayerTools and self.PlayerTools.Reset then pcall(self.PlayerTools.Reset) end
    if self.Movement and self.Movement.Reset then pcall(self.Movement.Reset) end
    if self.Visuals and self.Visuals.Reset then pcall(self.Visuals.Reset) end

    if self.UI and self.UI.Library and self.UI.Library.Unload and not self.UI.Library.Unloaded then
        pcall(function() self.UI.Library:Unload() end)
    end

    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(self.Connections)
    for _, d in ipairs(self.Drawings) do pcall(function() d.Visible = false d:Remove() end) end
    table.clear(self.Drawings)

    if ENV.ENDHUB == self then ENV.ENDHUB = nil end
    print("[EndHub] unloaded")
end

for _, path in ipairs(order) do loadModule(path) end

if not ENV.ENDHUB_WORK_LOADING then
    loadModule("modules/fps_patch.lua")
    loadModule("modules/server_cycle.lua")
    loadModule("modules/menu_first_screen_patch.lua")
    loadModule("modules/server_hop_quality_patch.lua")
    H.State.Ready = true
    H.ServerCycle.Bootstrap()
    if H.Features then H.Features.Load() end
end

print("[EndHub] COMPLETE modular build loaded")
return H
