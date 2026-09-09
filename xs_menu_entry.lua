-- EndHub XS menu helper
-- Uses only visible GUI state and normal mouse input.
local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer
while not player do task.wait(0.1) player = Players.LocalPlayer end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.ENDHUB_XS_MENU_STOP then ENV.ENDHUB_XS_MENU_STOP() end
local alive = true
ENV.ENDHUB_XS_MENU_STOP = function() alive = false end

local function norm(v)
    return tostring(v or ""):lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function visible(pg, obj)
    local n = obj
    while n and n ~= pg do
        if n:IsA("GuiObject") and not n.Visible then return false end
        if n:IsA("ScreenGui") and not n.Enabled then return false end
        n = n.Parent
    end
    return n == pg
end

local function ancestorButton(pg, obj)
    local n = obj
    for _ = 1, 6 do
        if not n or n == pg then break end
        if n:IsA("GuiButton") and visible(pg, n) then return n end
        n = n.Parent
    end
end

local function click(obj)
    if not obj or not obj:IsA("GuiObject") then return false end
    local p, s = obj.AbsolutePosition, obj.AbsoluteSize
    if s.X <= 0 or s.Y <= 0 then return false end
    local x, y = p.X + s.X/2, p.Y + s.Y/2
    return pcall(function()
        VIM:SendMouseMoveEvent(x, y, game)
        task.wait(0.04)
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.08)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

local function currentServer(pg)
    local sg = pg:FindFirstChild("ServerMenuGui")
    local outer = sg and sg:FindFirstChild("Frame")
    local main = outer and outer:FindFirstChild("MainFrame")
    local list = main and main:FindFirstChild("ScrollingFrame")
    if not list or not visible(pg, list) then return nil end
    for _, row in ipairs(list:GetChildren()) do
        local f = row:FindFirstChild("Frame")
        local label = f and f:FindFirstChild("ServerName")
        local text = label and norm(label.Text) or ""
        if row:IsA("GuiButton") and visible(pg, row)
            and (text:find("current server",1,true) or text:find("servidor atual",1,true)) then
            return row, "CURRENT SERVER"
        end
    end
end

local function target()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local cur, kind = currentServer(pg)
    if cur then return cur, kind end
    local endure, slotOne, play
    for _, obj in ipairs(pg:GetDescendants()) do
        if visible(pg,obj) and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
            local text = norm(obj.Text)
            local b = obj:IsA("GuiButton") and obj or ancestorButton(pg,obj)
            if b then
                if text == "endure" or text == "resistir" or text == "resist" then endure = b
                elseif text == "slot 1" or text == "slot1" then slotOne = b
                elseif text == "play" or text == "jogar" then play = b end
            end
        end
    end
    if endure then return endure,"ENDURE" end
    if slotOne then return slotOne,"SLOT 1" end
    if play then return play,"PLAY" end
end

local last = 0
task.spawn(function()
    while alive do
        local obj, kind = target()
        if obj and tick()-last >= 1.2 then
            last = tick()
            local ok = click(obj)
            print("[EndHub XS Menu] "..tostring(kind).." | "..(ok and "clicked" or "click failed"))
        end
        task.wait(0.25)
    end
end)
print("[EndHub XS Menu] auto menu helper loaded")
