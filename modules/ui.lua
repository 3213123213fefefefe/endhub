return function(H)
    local UIS = H.S.UIS
    H.UI = {Visible=true, ActiveTab="Botting", Controls={}, Tabs={}, Position=Vector2.new(820,175)}
    local U = H.UI

    local colors = {
        Bg = Color3.fromRGB(19,20,25),
        Top = Color3.fromRGB(15,16,20),
        Group = Color3.fromRGB(24,25,31),
        Control = Color3.fromRGB(30,31,38),
        Accent = Color3.fromRGB(94,70,190),
        Text = Color3.fromRGB(225,225,230),
        Sub = Color3.fromRGB(155,155,165),
        Success = Color3.fromRGB(90,200,120),
    }

    local function square(x,y,w,h,color)
        local d = Drawing.new("Square")
        d.Filled = true d.Color = color d.Size = Vector2.new(w,h)
        d.Position = U.Position + Vector2.new(x,y) d.Visible = true
        H.Drawings[#H.Drawings+1] = d
        return d
    end

    local function text(x,y,value,size,color)
        local d = Drawing.new("Text")
        d.Text = value d.Size = size or 14 d.Color = color or colors.Text
        d.Outline = true d.Position = U.Position + Vector2.new(x,y) d.Visible = true
        H.Drawings[#H.Drawings+1] = d
        return d
    end

    local function register(obj, tab, rel)
        U.Controls[#U.Controls+1] = obj
        obj.Tab = tab
        obj.Rel = rel
        return obj
    end

    local function setVis(obj, value)
        if obj.Bg then obj.Bg.Visible = value end
        if obj.Txt then obj.Txt.Visible = value end
        if obj.Mark then obj.Mark.Visible = value and obj.Value end
        if obj.Extra then
            for _,d in ipairs(obj.Extra) do d.Visible = value end
        end
    end

    function U.Refresh()
        for _, c in ipairs(U.Controls) do
            local show = U.Visible and (not c.Tab or c.Tab == U.ActiveTab)
            setVis(c, show)
        end
        for name, tab in pairs(U.Tabs) do
            tab.Bg.Color = name == U.ActiveTab and colors.Accent or colors.Control
        end
    end

    local win = register({Bg=square(0,0,600,430,colors.Bg)}, nil)
    local top = register({Bg=square(0,0,600,38,colors.Top)}, nil)
    register({Bg=square(0,38,600,2,colors.Accent)}, nil)
    register({Txt=text(14,10,"EndHub | Modular",16,colors.Text)}, nil)
    register({Txt=text(455,11,"Fable Edition",13,colors.Sub)}, nil)

    local tabNames = {"Botting","Sell","Movement","Visuals","Keybinds"}
    local tx = 14
    for _, name in ipairs(tabNames) do
        local w = name == "Movement" and 84 or name == "Keybinds" and 82 or 70
        local bg = square(tx,48,w,26,colors.Control)
        local label = text(tx+9,54,name,13,colors.Text)
        local c = register({Type="Tab",Bg=bg,Txt=label,X=tx,Y=48,W=w,H=26,Name=name},nil)
        U.Tabs[name] = c
        tx = tx + w + 6
    end

    local function group(tab,x,y,w,h,title)
        register({Bg=square(x,y,w,h,colors.Group)},tab)
        register({Txt=text(x+10,y+8,title,14,colors.Text)},tab)
        return {Tab=tab,X=x,Y=y,W=w,H=h}
    end

    local function button(g,y,label,cb)
        local x=g.X+10 local ay=g.Y+y local w=g.W-20
        local c={Type="Button",Bg=square(x,ay,w,28,colors.Control),Txt=text(x+8,ay+6,label,13,colors.Text),X=x,Y=ay,W=w,H=28,Callback=cb}
        return register(c,g.Tab)
    end

    local function toggle(g,y,label,getter,setter)
        local x=g.X+10 local ay=g.Y+y
        local val = getter()
        local c={Type="Toggle",Bg=square(x,ay,16,16,colors.Control),Mark=square(x+3,ay+3,10,10,colors.Accent),Txt=text(x+24,ay+1,label,13,colors.Text),X=x,Y=ay,W=g.W-20,H=18,Value=val,Getter=getter,Setter=setter}
        c.Mark.Visible = val
        return register(c,g.Tab)
    end

    local function label(g,y,value)
        return register({Txt=text(g.X+10,g.Y+y,value,13,colors.Sub)},g.Tab)
    end

    -- BOT
    local bg = group("Botting",14,86,278,328,"Trinket Bot")
    local bs = group("Botting",306,86,280,328,"Status")
    button(bg,38,"Start Trinket Bot",function() H.Farm.Start() end)
    button(bg,72,"Pause Trinket Bot",function() H.Farm.Stop() end)
    toggle(bg,112,"Auto Pickup [E]",function() return H.Config.AutoPickup end,function(v) H.Config.AutoPickup=v end)
    toggle(bg,138,"Bot Noclip",function() return H.Config.BotNoclip end,function(v) H.Config.BotNoclip=v end)
    toggle(bg,174,"Farm -> Full -> Sell",function() return H.Config.AutoFarmSell end,function(v)
        H.Config.AutoFarmSell=v
        H.State.FarmSellPhase="FARM"
        if v then H.Sell.Stop() H.Farm.Start() else H.Sell.Stop() H.Farm.Stop() end
    end)
    H.UI.BotStatus = label(bs,40,"Status: IDLE")
    H.UI.Capacity = label(bs,66,"Capacity: --/--")
    H.UI.Trinkets = label(bs,92,"Trinkets: 0")
    H.UI.Collected = label(bs,118,"Collected: 0")
    H.UI.SellerCache = label(bs,144,"Seller pos: --")
    label(bs,196,"F6 Farm | F8 Farm+Sell")
    label(bs,220,"RightShift UI | F7 Unload")

    -- SELL
    local sg = group("Sell",14,86,260,328,"Rarity")
    local cg = group("Sell",288,86,298,328,"Selected Rarity")
    U.SelectedRarity = "Common"
    U.RarityButtons = {}
    U.CategoryToggles = {}
    for i, rarity in ipairs(H.SellRarities) do
        local b = button(sg,32+(i-1)*31,rarity,function()
            U.SelectedRarity = rarity
            U.RefreshSellSelection()
        end)
        b.Rarity = rarity U.RarityButtons[#U.RarityButtons+1]=b
    end
    U.SellHeader = label(cg,34,"Rarity: Common")
    for i, cat in ipairs(H.SellCategories) do
        local t = toggle(cg,58+(i-1)*24,cat,function()
            local bucket=H.Config.SellByRarity[U.SelectedRarity]
            return bucket and bucket[cat] or false
        end,function(v)
            H.Sell.SetFilter(U.SelectedRarity,cat,v)
        end)
        t.Category=cat U.CategoryToggles[#U.CategoryToggles+1]=t
    end
    button(cg,280,"SELL MATCHING NOW",function() H.Sell.SellMatching() end)
    H.UI.SellStatus = label(cg,314,"Status: IDLE")

    function U.RefreshSellSelection()
        U.SellHeader.Txt.Text = "Rarity: " .. U.SelectedRarity
        for _, t in ipairs(U.CategoryToggles) do
            local bucket=H.Config.SellByRarity[U.SelectedRarity]
            t.Value = bucket and bucket[t.Category] or false
        end
        U.Refresh()
    end

    -- MOVEMENT
    local mg = group("Movement",14,86,572,328,"Movement")
    toggle(mg,42,"Fly",function() return H.Config.MovementFly end,function(v) H.Config.MovementFly=v end)
    toggle(mg,70,"Noclip",function() return H.Config.MovementNoclip end,function(v) H.Config.MovementNoclip=v end)
    button(mg,108,"Fly speed -10",function() H.Config.MovementFlySpeed=math.max(10,H.Config.MovementFlySpeed-10) end)
    button(mg,142,"Fly speed +10",function() H.Config.MovementFlySpeed=math.min(250,H.Config.MovementFlySpeed+10) end)
    button(mg,176,"Walk speed -4",function() H.Config.WalkSpeed=math.max(16,H.Config.WalkSpeed-4) end)
    button(mg,210,"Walk speed +4",function() H.Config.WalkSpeed=math.min(100,H.Config.WalkSpeed+4) end)
    H.UI.MoveStatus = label(mg,260,"Fly: 70 | Walk: 16")

    -- VISUALS
    local vg = group("Visuals",14,86,572,328,"Visuals")
    toggle(vg,42,"NPC ESP",function() return H.Config.NPCESP end,function(v) H.Config.NPCESP=v end)
    toggle(vg,70,"Player ESP",function() return H.Config.PlayerESP end,function(v) H.Config.PlayerESP=v end)
    toggle(vg,98,"No Fog",function() return H.Config.NoFog end,function(v) H.Config.NoFog=v end)
    toggle(vg,126,"Fullbright",function() return H.Config.Fullbright end,function(v) H.Config.Fullbright=v end)
    button(vg,166,"Brightness +1",function() H.Config.FullbrightBrightness=math.min(10,H.Config.FullbrightBrightness+1) end)
    button(vg,200,"Brightness -1",function() H.Config.FullbrightBrightness=math.max(1,H.Config.FullbrightBrightness-1) end)
    H.UI.VisualStatus = label(vg,250,"Brightness: 4")

    -- KEYBINDS placeholder; keybind module fills rows
    U.KeyGroup = group("Keybinds",14,86,572,328,"Click a row, then press a key")

    function U.AddKeybindRow(y, action)
        local g=U.KeyGroup local x=g.X+10 local ay=g.Y+y local w=g.W-20
        local c={Type="Keybind",Bg=square(x,ay,w,25,colors.Control),Txt=text(x+8,ay+5,action.Label.."   ["..(action.Key and action.Key.Name or "NONE").."]",13,colors.Text),X=x,Y=ay,W=w,H=25,Action=action}
        return register(c,"Keybinds")
    end

    local function hit(c,mx,my)
        local p=U.Position
        return mx>=p.X+c.X and mx<=p.X+c.X+c.W and my>=p.Y+c.Y and my<=p.Y+c.Y+c.H
    end

    C = H.Core
    C.Connect(UIS.InputBegan,function(input,gp)
        if H.State.Unloaded or gp then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local m=UIS:GetMouseLocation()
        for _,c in ipairs(U.Controls) do
            if c.Type=="Tab" and hit(c,m.X,m.Y) then U.ActiveTab=c.Name U.Refresh() return end
            if U.Visible and c.Tab==U.ActiveTab and hit(c,m.X,m.Y) then
                if c.Type=="Button" and c.Callback then task.spawn(c.Callback) return end
                if c.Type=="Toggle" then c.Value=not c.Value c.Setter(c.Value) U.Refresh() return end
                if c.Type=="Keybind" and H.Keybinds then H.Keybinds.Capturing=c.Action U.Refresh() return end
            end
        end
    end)

    task.spawn(function()
        while not H.State.Unloaded do
            pcall(function()
                H.Core.ReadCapacity()
                H.UI.BotStatus.Txt.Text="Status: "..tostring(H.State.Status).." | Sell: "..tostring(H.State.SellStatus)
                H.UI.Capacity.Txt.Text="Capacity: "..tostring(H.State.InventoryCurrent).."/"..tostring(H.State.InventoryMax)
                H.UI.Trinkets.Txt.Text="Trinkets: "..tostring(H.State.Detected)
                H.UI.Collected.Txt.Text="Collected: "..tostring(H.State.Collected)
                local s=H.Core.GetSavedSeller()
                H.UI.SellerCache.Txt.Text=s and ("Seller pos: "..math.floor(s.X)..","..math.floor(s.Y)..","..math.floor(s.Z)) or "Seller pos: VISIT CLEMENT"
                H.UI.SellStatus.Txt.Text="Status: "..tostring(H.State.SellStatus)
                H.UI.MoveStatus.Txt.Text="Fly: "..tostring(H.Config.MovementFlySpeed).." | Walk: "..tostring(H.Config.WalkSpeed)
                H.UI.VisualStatus.Txt.Text="Brightness: "..tostring(H.Config.FullbrightBrightness)
                for _,t in ipairs(U.CategoryToggles) do
                    local b=H.Config.SellByRarity[U.SelectedRarity]
                    t.Value=b and b[t.Category] or false
                end
                U.Refresh()
            end)
            task.wait(0.35)
        end
    end)

    U.RefreshSellSelection()
    U.Refresh()
end
