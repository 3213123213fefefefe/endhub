return function(H)
    local UI = H.UI
    if not UI or not UI.Library then return end

    local ENV = getgenv()
    ENV.ENDHUB_KEYBINDS = ENV.ENDHUB_KEYBINDS or {}
    local saved = ENV.ENDHUB_KEYBINDS

    -- Enum.KeyCode.Unknown also appears on mouse input, so using it as the
    -- window toggle key can make left-click open/close the UI. Always install
    -- a real keyboard key immediately after the window is created.
    local name = tostring(saved.menu_toggle or "Insert")
    if not Enum.KeyCode[name] then name = "Insert" end
    saved.menu_toggle = name
    saved.feature_show_ui = nil
    UI.Library.ToggleKeybind = Enum.KeyCode[name]

    if H.Core and H.Core.SaveKeybinds then
        pcall(H.Core.SaveKeybinds)
    end

    print("[EndHub] menu key ready | " .. name)
end
