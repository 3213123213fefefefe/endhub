return function(H)
    if H.PickupSpy then return H.PickupSpy end

    local UIS = H.S and H.S.UIS or game:GetService("UserInputService")
    local ENV = getgenv()

    local P = {
        Armed = false,
        CaptureUntil = 0,
        LastLines = {},
        LastStatus = "IDLE",
        Hooked = false,
        File = "EndHub/pickup_remote_capture.txt",
    }
    H.PickupSpy = P

    local function setStatus(text)
        P.LastStatus = tostring(text or "")
        print("[EndHub PickupSpy] " .. P.LastStatus)
    end

    local function safeFullName(obj)
        if typeof(obj) ~= "Instance" then return tostring(obj) end
        local ok, name = pcall(function() return obj:GetFullName() end)
        return ok and name or tostring(obj)
    end

    local function encode(value, depth, seen)
        depth = depth or 0
        seen = seen or {}
        if depth > 3 then return "<depth-limit>" end

        local t = typeof(value)
        if t == "Instance" then return safeFullName(value) end
        if t == "string" then return string.format("%q", value) end
        if t == "Vector3" or t == "CFrame" or t == "Color3" or t == "EnumItem" then return tostring(value) end
        if t ~= "table" then return tostring(value) end
        if seen[value] then return "<cycle>" end
        seen[value] = true

        local out, n = {}, 0
        for k, v in pairs(value) do
            n = n + 1
            if n > 20 then out[#out + 1] = "..." break end
            out[#out + 1] = "[" .. encode(k, depth + 1, seen) .. "]=" .. encode(v, depth + 1, seen)
        end
        seen[value] = nil
        return "{" .. table.concat(out, ", ") .. "}"
    end

    local function appendLine(line)
        P.LastLines[#P.LastLines + 1] = line
        while #P.LastLines > 60 do table.remove(P.LastLines, 1) end
        print(line)

        if type(writefile) == "function" then
            pcall(function()
                local text = table.concat(P.LastLines, "\n")
                writefile(P.File, text)
            end)
        end
    end

    local function captureRemote(remote, method, args)
        if not P.Armed or tick() > P.CaptureUntil then return end
        if typeof(remote) ~= "Instance" then return end
        if method ~= "FireServer" and method ~= "InvokeServer" then return end
        if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then return end

        local parts = {}
        for i = 1, math.min(args.n or #args, 20) do
            parts[#parts + 1] = encode(args[i])
        end

        local line = string.format(
            "[EndHub PickupSpy] %s:%s(%s)",
            safeFullName(remote),
            method,
            table.concat(parts, ", ")
        )
        appendLine(line)
    end

    function P.Clear()
        table.clear(P.LastLines)
        if type(writefile) == "function" then
            pcall(function() writefile(P.File, "") end)
        end
        setStatus("CAPTURE CLEARED")
    end

    function P.Arm(seconds)
        seconds = math.max(3, tonumber(seconds) or 8)
        P.Armed = true
        P.CaptureUntil = tick() + seconds
        P.LastLines = {}
        setStatus("ARMED FOR " .. tostring(seconds) .. "s | PRESS E ON ONE TRINKET")

        task.delay(seconds, function()
            if H.State and H.State.Unloaded then return end
            if P.Armed and tick() >= P.CaptureUntil then
                P.Armed = false
                setStatus("CAPTURE FINISHED | " .. tostring(#P.LastLines) .. " REMOTE CALL(S)")
            end
        end)
    end

    function P.Stop()
        P.Armed = false
        P.CaptureUntil = 0
        setStatus("STOPPED")
    end

    local canHook = type(hookmetamethod) == "function"
        and type(getnamecallmethod) == "function"
        and type(newcclosure) == "function"

    if canHook then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if P.Armed and tick() <= P.CaptureUntil then
                local args = table.pack(...)
                pcall(captureRemote, self, method, args)
            end
            return oldNamecall(self, ...)
        end))
        P.Hooked = true
        setStatus("READY")
    else
        setStatus("UNSUPPORTED: hookmetamethod/getnamecallmethod unavailable")
    end

    if H.Core and H.Core.Connect then
        H.Core.Connect(UIS.InputBegan, function(input, processed)
            if processed or not P.Armed then return end
            if input.KeyCode == Enum.KeyCode.E then
                print("[EndHub PickupSpy] E pressed while capture armed")
            end
        end)
    end

    local UI = H.UI
    if UI and UI.Tabs and UI.Tabs.Interface then
        local group = UI.Tabs.Interface:AddRightGroupbox("Pickup Remote Debug")
        group:AddLabel("Arm capture, walk next to ONE trinket, press E once, then send me the [EndHub PickupSpy] lines. It only logs outgoing remotes during the short capture window.", true)
        group:AddButton({Text = "ARM 8s PICKUP CAPTURE", Func = function() P.Arm(8) end})
        group:AddButton({Text = "STOP CAPTURE", Func = function() P.Stop() end})
        group:AddButton({Text = "CLEAR CAPTURE", Func = function() P.Clear() end})
        group:AddLabel("EH_PickupSpyStatus", {Text = "PickupSpy: " .. P.LastStatus, DoesWrap = true})

        task.spawn(function()
            while not (H.State and H.State.Unloaded) do
                local option = UI.Options and UI.Options.EH_PickupSpyStatus
                if option and type(option.SetText) == "function" then
                    local remain = P.Armed and math.max(0, P.CaptureUntil - tick()) or 0
                    option:SetText(string.format("PickupSpy: %s | calls=%d | %.1fs", P.LastStatus, #P.LastLines, remain))
                end
                task.wait(0.25)
            end
        end)
    end

    print("[EndHub] pickup remote debugger loaded")
    return P
end
