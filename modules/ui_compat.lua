return function(H)
    H.UICompat = {}
    local R = H.S.RunService
    local UIS = H.S.UIS
    local Library = H.UI and H.UI.Library

    -- Hydroxide's custom cursor binds a RenderStep named "ShowCursor".
    -- Some executor environments do not provide everything that cursor loop
    -- expects, which can spam "attempt to call a nil value" every frame while
    -- the rest of the UI continues to work. EndHub does not need the custom
    -- cursor, so disable only that optional renderer and keep Roblox's cursor.
    if Library then
        Library.ShowCustomCursor = false
    end

    pcall(function()
        R:UnbindFromRenderStep("ShowCursor")
    end)

    pcall(function()
        UIS.MouseIconEnabled = true
    end)

    function H.UICompat.Reset()
        pcall(function()
            R:UnbindFromRenderStep("ShowCursor")
        end)
        pcall(function()
            UIS.MouseIconEnabled = true
        end)
    end

    print("[EndHub] Hydroxide cursor compatibility patch loaded")
end

