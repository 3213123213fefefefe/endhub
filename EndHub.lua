local ENV = getgenv()

if ENV.ENDHUB and ENV.ENDHUB.Unload then
    pcall(function() ENV.ENDHUB:Unload() end)
end

local H = {
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
        Desync = false,
        DesyncOffset = 2.5,
        DesyncRate = 10,

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
    },
    State = {
        Running = false,
        Unloaded = false,
        Status = "IDLE",
        SellStatus = "IDLE",
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
    "modules/farm.lua",
    "modules/sell.lua",
    "modules/movement.lua",
    "modules/players.lua",
    "modules/visuals.lua",
    "modules/ui.lua",
    "modules/ui_compat.lua",
    "modules/seller_tools.lua",
    "modules/legacy_features.lua",
    "modules/keybinds.lua",
}

for _, path in ipairs(order) do loadModule(path) end

function H:Unload()
    if self.State.Unloaded then return end
    self.State.Unloaded = true
    self.State.Running = false
    self.Config.AutoSell = false
    self.Config.AutoFarmSell = false

    if self.Farm and self.Farm.Stop then pcall(self.Farm.Stop) end
    if self.Sell and self.Sell.Stop then pcall(self.Sell.Stop) end
    if self.PlayerTools and self.PlayerTools.Reset then pcall(self.PlayerTools.Reset) end
    if self.Movement and self.Movement.Reset then pcall(self.Movement.Reset) end
    if self.Visuals and self.Visuals.Reset then pcall(self.Visuals.Reset) end
    if self.Legacy and self.Legacy.Reset then pcall(self.Legacy.Reset) end
    if self.UICompat and self.UICompat.Reset then pcall(self.UICompat.Reset) end

    if self.UI and self.UI.Library and self.UI.Library.Unload and not self.UI.Library.Unloaded then
        pcall(function() self.UI.Library:Unload() end)
    end

    for _, c in ipairs(self.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(self.Connections)

    for _, d in ipairs(self.Drawings) do
        pcall(function() d.Visible = false d:Remove() end)
    end
    table.clear(self.Drawings)

    if ENV.ENDHUB == self then ENV.ENDHUB = nil end
    print("[EndHub] unloaded")
end

print("[EndHub] COMPLETE modular build loaded")
return H
