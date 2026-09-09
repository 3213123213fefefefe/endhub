-- EndHub XS staged menu driver for executors with partial input support.
-- It only targets the known Play, Slot 1 and Current Server controls.
local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer
while not player do task.wait(0.1) player = Players.LocalPlayer end

local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.ENDHUB_XS_MENU_STOP then ENV.ENDHUB_XS_MENU_STOP() end

local driver = {
    Alive = true,
    Stage = "WAIT GUI",
    Attempt = 0,
    LastClick = 0,
    LastTarget = nil,
    LastMethod = nil,
}
ENV.ENDHUB_XS_MENU_DRIVER = driver
ENV.ENDHUB_XS_MENU_STOP = function() driver.Alive = false end

local function norm(v)
    return tostring(v or ""):lower():gsub("<[^>]+>", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function visible(pg, obj)
    if not obj then return false end
    local node = obj
    while node and node ~= pg do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node = node.Parent
    end
    return node == pg
end

local function descend(root, ...)
    local node = root
    for i = 1, select("#", ...) do
        node = node and node:FindFirstChild(select(i, ...))
    end
    return node
end

local function ancestorButton(pg, obj)
    local node = obj
    for _ = 1, 8 do
        if not node or node == pg then return nil end
        if node:IsA("GuiButton") and visible(pg, node) then return node end
        node = node.Parent
    end
end

local function textButton(pg, root, accepted)
    if not root or not visible(pg, root) then return nil end
    for _, obj in ipairs(root:GetDescendants()) do
        if visible(pg, obj) and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
            if accepted[norm(obj.Text)] then
                return obj:IsA("GuiButton") and obj or ancestorButton(pg, obj)
            end
        end
    end
end

local function currentServer(pg, menu)
    local list = descend(menu, "Frame", "MainFrame", "ScrollingFrame")
    if not list or not visible(pg, list) then return nil end
    for _, row in ipairs(list:GetChildren()) do
        local label = descend(row, "Frame", "ServerName")
        local name = label and norm(label.Text) or ""
        if row:IsA("GuiButton") and visible(pg, row)
            and (name:find("current server", 1, true)
                or name:find("servidor atual", 1, true)) then
            return row
        end
    end
end

function driver.Target()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil, "WAIT PLAYERGUI" end

    -- Screen order is authoritative. Hidden templates from another screen can
    -- contain the same words, so never select globally before checking it.
    local serverMenu = pg:FindFirstChild("ServerMenuGui")
    if serverMenu and visible(pg, serverMenu) then
        return currentServer(pg, serverMenu), "CURRENT SERVER"
    end

    local slots = pg:FindFirstChild("SaveSlotsGui")
    if slots and visible(pg, slots) then
        local exact = descend(slots, "Frame", "ScrollingFrame", "SaveSlot_1", "ButtonsFrame", "PlayButton")
        if exact and exact:IsA("GuiButton") and visible(pg, exact) then return exact, "SLOT 1 PLAY" end
        local slot = descend(slots, "Frame", "ScrollingFrame", "SaveSlot_1")
        return textButton(pg, slot, {endure=true, play=true, jogar=true}), "SLOT 1 PLAY"
    end

    local main = pg:FindFirstChild("MainMenuGui")
    if main and visible(pg, main) then
        local exact = descend(main, "Frame", "PlayButton")
        if exact and exact:IsA("GuiButton") and visible(pg, exact) then return exact, "MAIN PLAY" end
        return textButton(pg, main, {endure=true, play=true, jogar=true}), "MAIN PLAY"
    end

    return nil, "IN GAME / WAIT MENU"
end

local function fireSignal(button, name)
    if type(firesignal) ~= "function" then return false end
    local signal = button[name]
    if not signal then return false end
    if name == "MouseButton1Down" then
        local p, s = button.AbsolutePosition, button.AbsoluteSize
        firesignal(signal, p.X + s.X / 2, p.Y + s.Y / 2)
    elseif name == "Activated" then
        firesignal(signal, nil, 1)
    else
        firesignal(signal)
    end
    return true
end

local function activateMethod(button)
    local ok, result = pcall(function()
        local activate = button.Activate
        if type(activate) ~= "function" then return false end
        activate(button)
        return true
    end)
    return ok and result == true
end

local function mouse(button)
    local p, s = button.AbsolutePosition, button.AbsoluteSize
    if s.X <= 0 or s.Y <= 0 then return false end
    local x, y = p.X + s.X / 2, p.Y + s.Y / 2
    VIM:SendMouseMoveEvent(x, y, game)
    task.wait(0.04)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.08)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    return true
end

local function selectedObject(button)
    GuiService.SelectedObject = button
    VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.06)
    VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    return true
end

local methods = {
    {"ACTIVATE", activateMethod},
    {"CONNECTIONS", function(b)
        if type(getconnections) ~= "function" then return false end
        for _, signalName in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down"}) do
            local ok, connections = pcall(getconnections, b[signalName])
            if ok then
                for _, connection in ipairs(connections or {}) do
                    local callback = connection.Function or connection.Callback
                    if type(callback) == "function" then
                        pcall(callback)
                        return true
                    end
                    if type(connection.Fire) == "function" then
                        pcall(function() connection:Fire() end)
                        return true
                    end
                end
            end
        end
        return false
    end},
    {"SIGNAL ACTIVATED", function(b) return fireSignal(b, "Activated") end},
    {"SIGNAL CLICK", function(b) return fireSignal(b, "MouseButton1Click") end},
    {"MOUSE", mouse},
    {"SELECT + ENTER", selectedObject},
    {"VIRTUAL USER", function(b)
        local p, s = b.AbsolutePosition, b.AbsoluteSize
        local camera = workspace.CurrentCamera
        local cameraCFrame = camera and camera.CFrame or CFrame.new()
        VirtualUser:Button1Down(Vector2.new(p.X + s.X/2, p.Y + s.Y/2), cameraCFrame)
        task.wait(0.08)
        VirtualUser:Button1Up(Vector2.new(p.X + s.X/2, p.Y + s.Y/2), cameraCFrame)
        return true
    end},
}

function driver.Step(force)
    local button, stage = driver.Target()
    driver.Stage = stage
    if not button then return stage ~= "IN GAME / WAIT MENU", false end
    if not force and tick() - driver.LastClick < 1.1 then return true, false end
    if button ~= driver.LastTarget then
        driver.LastTarget = button
        driver.Attempt = 0
    end
    driver.Attempt = driver.Attempt + 1
    driver.LastClick = tick()
    local method = methods[(driver.Attempt - 1) % #methods + 1]
    local ok, result = pcall(method[2], button)
    driver.LastMethod = method[1]
    print("[EndHub XS Menu] " .. stage .. " | method=" .. method[1]
        .. " | attempt=" .. driver.Attempt .. " | " .. (ok and result and "sent" or "failed")
        .. " | " .. button:GetFullName())
    return true, ok and result == true
end

task.spawn(function()
    while driver.Alive do
        -- This must remain independent: ServerCycle can still be waiting while
        -- the player is on Endure / save-slot / current-server screens.
        pcall(driver.Step)
        task.wait(0.20)
    end
end)

print("[EndHub XS Menu] staged auto-entry loaded")
return driver
