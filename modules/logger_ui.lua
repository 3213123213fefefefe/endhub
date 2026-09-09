return function(H)
    local group = H.UI.Tabs.Sell:AddLeftGroupbox("Session log")
    local connection
    group:AddButton({Text = "Capture this instance's logs", Func = function()
        if connection or type(appendfile) ~= "function" then return end
        local id = H.S.HttpService:GenerateGUID(false):gsub("[^%w_-]", "_")
        local path = H.Persistence.Dir .. "/log-" .. id .. ".txt"
        local ok, err = pcall(writefile, path, "EndHub account=" .. tostring(H.S.Player.UserId) .. " job=" .. tostring(game.JobId) .. "\n")
        if not ok then warn("[EndHub Log] " .. tostring(err)) return end
        connection = H.Core.Connect(game:GetService("LogService").MessageOut, function(message)
            if tostring(message):lower():find("[endhub", 1, true) then
                -- Optional logger, private filename. No global __namecall hook.
                pcall(appendfile, path, tostring(message) .. "\n")
            end
        end)
        print("[EndHub Log] " .. path)
    end})
    group:AddButton({Text = "Stop log capture", Func = function()
        if connection then connection:Disconnect() connection = nil end
    end})
end
