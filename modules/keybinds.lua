return function(H)
    H.Keybinds = {Actions={}, Capturing=nil}
    local K = H.Keybinds
    local UIS = H.S.UIS
    local saved = getgenv().ENDHUB_KEYBINDS

    local function savedKey(id, fallback)
        local name = saved[id]
        if type(name)=="string" and Enum.KeyCode[name] then
            return Enum.KeyCode[name]
        end
        return fallback
    end

    local function add(id,label,key,callback)
        local a={Id=id,Label=label,Key=savedKey(id,key),Callback=callback}
        K.Actions[#K.Actions+1]=a
        return a
    end

    local function setKey(action,key)
        for _,other in ipairs(K.Actions) do
            if other~=action and other.Key==key then
                other.Key=nil
                saved[other.Id]=nil
            end
        end
        action.Key=key
        saved[action.Id]=key and key.Name or nil
        for _,c in ipairs(H.UI.Controls) do
            if c.Type=="Keybind" and c.Action==action then
                c.Txt.Text=action.Label.."   ["..(action.Key and action.Key.Name or "NONE").."]"
            elseif c.Type=="Keybind" and c.Action then
                c.Txt.Text=c.Action.Label.."   ["..(c.Action.Key and c.Action.Key.Name or "NONE").."]"
            end
        end
    end

    local function toggleFarm()
        if H.State.Running then H.Farm.Stop() else H.Farm.Start() end
    end

    local function toggleFarmSell()
        H.Config.AutoFarmSell=not H.Config.AutoFarmSell
        H.State.FarmSellPhase="FARM"
        if H.Config.AutoFarmSell then
            H.Sell.Stop()
            H.Farm.Start()
        else
            H.Sell.Stop()
            H.Farm.Stop()
        end
    end

    local actions = {
        add("farm_toggle","Trinket Bot",Enum.KeyCode.F6,toggleFarm),
        add("farm_sell","Farm -> Full -> Sell",Enum.KeyCode.F8,toggleFarmSell),
        add("fly_toggle","Movement Fly",Enum.KeyCode.F3,function() H.Config.MovementFly=not H.Config.MovementFly end),
        add("noclip_toggle","Movement Noclip",Enum.KeyCode.F4,function() H.Config.MovementNoclip=not H.Config.MovementNoclip end),
        add("npc_esp","NPC ESP",Enum.KeyCode.F5,function() H.Config.NPCESP=not H.Config.NPCESP end),
        add("ui_toggle","Show / Hide UI",Enum.KeyCode.RightShift,function() H.UI.Visible=not H.UI.Visible H.UI.Refresh() end),
        add("unload","Unload Script",Enum.KeyCode.F7,function() H:Unload() end),
    }

    for i,a in ipairs(actions) do
        H.UI.AddKeybindRow(36+(i-1)*34,a)
    end
    H.UI.Refresh()

    H.Core.Connect(UIS.InputBegan,function(input,gp)
        if H.State.Unloaded then return end

        if K.Capturing then
            if input.UserInputType==Enum.UserInputType.Keyboard then
                local key=input.KeyCode
                if key==Enum.KeyCode.Escape or key==Enum.KeyCode.Backspace or key==Enum.KeyCode.Delete then
                    setKey(K.Capturing,nil)
                elseif key~=Enum.KeyCode.Unknown then
                    setKey(K.Capturing,key)
                end
                K.Capturing=nil
                H.UI.Refresh()
            end
            return
        end

        if gp or input.UserInputType~=Enum.UserInputType.Keyboard then return end
        for _,a in ipairs(K.Actions) do
            if a.Key and input.KeyCode==a.Key then
                task.spawn(a.Callback)
                return
            end
        end
    end)

    print("[EndHub] keybinds loaded")
end
