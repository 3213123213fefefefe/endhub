-- Deterministic movement/lifecycle checks; no Roblox process or network access.
local output = print
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b) assert(math.abs(a - b) < 0.01, tostring(a) .. " ~= " .. tostring(b)) end
local function signal()
    local s = {connections = {}}
    function s:Connect(fn)
        local c = {Connected = true, Fn = fn}
        function c:Disconnect() self.Connected = false end
        self.connections[#self.connections + 1] = c
        return c
    end
    function s:Fire(...)
        for _, c in ipairs(self.connections) do if c.Connected then c.Fn(...) end end
    end
    return s
end
local function context(options)
    options = options or {}
    local t = {now = 0, jobs = {}, tweens = {}, hops = 0, pickups = 0, callbacks = {}}
    local vector = {}
    vector.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
    vector.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
    vector.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
    vector.__index = function(v,k)
        local n = math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z)
        if k == "Magnitude" then return n end
        if k == "Unit" then return Vector3.new(v.X/n,v.Y/n,v.Z/n) end
    end
    Vector3 = {new = function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vector) end}
    Vector3.zero = Vector3.new(0,0,0)
    local frame = {__mul = function(a) return a end}
    CFrame = {new = function(pos) return setmetatable({Position=pos,Rotation={}},frame) end}
    CFrame.lookAt = CFrame.new
    TweenInfo = {new = function(duration, easing) return {Time=duration,EasingStyle=easing} end}
    Enum = {EasingStyle={Linear="Linear"},PlaybackState={Completed="Completed",Cancelled="Cancelled"}}
    math.clamp = function(n,a,b) return math.max(a,math.min(n,b)) end
    table.clear = function(tab) for k in pairs(tab) do tab[k]=nil end end
    typeof = function(value) return getmetatable(value)==vector and "Vector3" or type(value) end
    tick = function() return t.now end
    print, warn = function() end, function() end
    task = {}
    local function enqueue(fn,delay)
        t.jobs[#t.jobs+1]={thread=coroutine.create(fn),at=t.now+(delay or 0)}
    end
    task.spawn = function(fn) enqueue(fn,0) end
    task.delay = function(delay,fn) enqueue(fn,delay) end
    task.wait = function(delay) return coroutine.yield(delay or 1/30) end
    local heartbeat, added = signal(),signal()
    local root = setmetatable({Parent=true,_frame=CFrame.new(Vector3.zero)}, {
        __index=function(r,k)
            if k=="Position" then return r._frame.Position end
            if k=="CFrame" then return r._frame end
        end,
        __newindex=function(r,k,v) if k=="CFrame" then rawset(r,"_frame",v) else rawset(r,k,v) end end,
    })
    local hum = {Health=100}
    local ts = {}
    function ts:Create(part, info, goal)
        local tw={Root=part,Info=info,Goal=goal.CFrame,Completed=signal(),From=part.Position}
        function tw:Play() self.Playing=true self.Started=t.now end
        function tw:Cancel() self.Playing=false self.Cancelled=true self.Completed:Fire("Cancelled") end
        function tw:Destroy() self.Destroyed=true end
        t.tweens[#t.tweens+1]=tw
        return tw
    end
    game={PlaceId=123,GetService=function(_,name) if name=="TweenService" then return ts end end}
    local player={Character={},CharacterAdded=added}
    function player:RequestStreamAroundAsync()
        if options.streamHang then task.wait(1000) end
    end
    local drops={children={},ChildRemoved=signal()}
    function drops:GetChildren() return self.children end
    local H={Config={FarmMoveMode=options.mode or "TP",FarmTweenSpeed=85,FarmFlySpeed=85,
        FarmTweenPauseSeconds=0,
        AutoPickup=true,BackgroundPickup=false,PickupDistance=7,TargetHeight=3,TargetTimeout=15,PickupInterval=0.3},
        State={Ready=true,Running=true,Unloaded=false,StartedAt=0,Collected=0,LastPickup=0,FarmSellPhase="FARM"},
        Connections={},S={RunService={Heartbeat=heartbeat},Player=player},Core={}}
    function H:Unload()
        self.State.Unloaded=true
        for _,c in ipairs(self.Connections) do c:Disconnect() end
    end
    H.Core={Root=function() return t.root end,Humanoid=function() return hum end,
        Noclip=function() end,DropsFolder=function() return drops end,
        IsTrinketDrop=function(obj) return obj and obj.Parent==drops end,
        DropPart=function(obj) return obj and obj.Part end,
        PressKey=function() t.pickups=t.pickups+1 return true end,
        Connect=function(s,fn) local c=s:Connect(fn) H.Connections[#H.Connections+1]=c return c end,
        Teleport=function() error("automated movement used direct teleport") end}
    t.H,t.root,t.hum,t.player,t.heartbeat,t.drops=H,root,hum,player,heartbeat,drops
    if options.segmented then H.Config.FarmTweenPauseSeconds = nil end
    assert(loadfile("modules/farm_movement.lua"))()(H)
    if options.farm then assert(loadfile("modules/farm.lua"))()(H) end
    if options.route then
        H.Farm={ClearTarget=function() H.State.CurrentTarget=nil H.FarmMovement.Cancel("loot") end,
            Allowed=function() return false end,Nearest=function() return nil end,Step=function() end,Start=function() H.State.Running=true end}
        H.Config.TrinketRoutes={["123"]=options.route}
        H.Config.TrinketRouteWait=2
        H.ServerCycle={OnLootComplete=function() t.hops=t.hops+1 H.State.Running=false return true end}
        local group=setmetatable({}, {__index=function(_,method)
            return function(_,id,info)
                if type(info)=="table" and info.Callback then t.callbacks[id]=info.Callback end
            end
        end})
        H.UI={Options={},Tabs={Botting={AddLeftGroupbox=function() return group end}}}
        assert(loadfile("modules/trinket_route.lua"))()(H)
        heartbeat:Connect(function(dt) H.Farm.Step(dt) end)
    end
    function t.advance(seconds)
        local finish=t.now+seconds
        while t.now<finish-0.000001 do
            local dt=math.min(1/30,finish-t.now)
            t.now=t.now+dt
            for _,tw in ipairs(t.tweens) do
                if tw.Playing then
                    local alpha=math.min(1,(t.now-tw.Started)/tw.Info.Time)
                    tw.Root.CFrame=CFrame.new(tw.From+(tw.Goal.Position-tw.From)*alpha)
                    if alpha>=1 then tw.Playing=false tw.Completed:Fire("Completed") end
                end
            end
            local i=1
            while i<=#t.jobs do
                local j=t.jobs[i]
                if j.at<=t.now then
                    table.remove(t.jobs,i)
                    local ok,delay=coroutine.resume(j.thread)
                    assert(ok,delay)
                    if coroutine.status(j.thread)~="dead" then j.at=t.now+delay t.jobs[#t.jobs+1]=j end
                else i=i+1 end
            end
            heartbeat:Fire(dt)
        end
    end
    return t
end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end

test("TP profiles migrate; speed determines duration without per-frame tween restarts",function()
    local t=context(); local m=t.H.FarmMovement; local dest=Vector3.new(170,0,0)
    equal(t.H.Config.FarmMoveMode,"Tween")
    equal(m.MoveTo(dest,nil,"loot"),false)
    near(t.tweens[1].Info.Time,2); equal(t.tweens[1].Info.EasingStyle,"Linear")
    for _=1,30 do m.MoveTo(dest,nil,"loot") end
    equal(#t.tweens,1); t.advance(1); near(t.root.Position.X,85)
    t.advance(1.1); equal(m.MoveTo(dest,nil,"loot"),true); equal(m.IsActive(),false)
end)
test("retargeting and changing speed cancel the previous tween",function()
    local t=context(); local m=t.H.FarmMovement
    m.MoveTo(Vector3.new(170,0,0),nil,"loot");t.advance(0.5)
    m.MoveTo(Vector3.new(340,0,0),nil,"loot");equal(t.tweens[1].Cancelled,true)
    t.H.Config.FarmTweenSpeed=170
    m.MoveTo(Vector3.new(340,0,0),nil,"loot");equal(t.tweens[2].Cancelled,true)
    near(t.tweens[3].Info.Time,(340-t.root.Position.X)/170)
    m.Cancel();local x=t.root.Position.X;t.advance(5);near(t.root.Position.X,x)
end)
test("pause, death, character replacement and unload cancel movement",function()
    for _,action in ipairs({"pause","death","character","unload"}) do
        local t=context();local m=t.H.FarmMovement
        m.MoveTo(Vector3.new(1000,0,0),nil,"loot");t.advance(0.5)
        if action=="pause" then t.H.State.Running=false
        elseif action=="death" then t.hum.Health=0
        elseif action=="character" then t.player.CharacterAdded:Fire()
        else t.H:Unload() end
        t.advance(0.05);equal(m.IsActive(),false)
        local x=t.root.Position.X;t.advance(5);near(t.root.Position.X,x)
    end
end)
test("sale takeover and role-check pause cannot leave the old route tween running",function()
    local t=context();local m=t.H.FarmMovement
    m.MoveTo(Vector3.new(1000,0,0),nil,"route");t.advance(0.3)
    t.H.Config.AutoSell=true;t.H.State.Running=false
    m.MoveTo(Vector3.new(200,0,0),nil,"seller")
    equal(t.tweens[1].Cancelled,true);equal(m.Active.Owner,"seller")
    t.H.ServerCycle={Checking=true};t.advance(0.1);equal(m.IsActive(),false)
end)
test("route delay and server-hop completion only start after actual arrival",function()
    local t=context({route={{340,0,0},{680,0,0}}})
    t.advance(1);equal(t.H.GetTrinketRouteStatus().Index,1);equal(t.hops,0)
    assert(t.root.Position.X>0 and t.root.Position.X<340)
    t.advance(3.5);near(t.root.Position.X,340)
    assert(t.H.GetTrinketRouteStatus().Remaining>1)
    t.advance(2);equal(t.H.GetTrinketRouteStatus().Index,2);equal(t.hops,0)
    t.advance(6);near(t.root.Position.X,680);equal(t.hops,1)
end)
test("pausing mid-route preserves the current destination for resume",function()
    local t=context({route={{340,0,0}}})
    t.advance(1);t.H.State.Running=false;t.advance(0.05)
    local x=t.root.Position.X;t.advance(3);near(t.root.Position.X,x)
    equal(t.H.GetTrinketRouteStatus().Index,1);equal(t.hops,0)
    t.H.State.Running=true;t.advance(6);near(t.root.Position.X,340);equal(t.hops,1)
end)
test("stream timeouts allow travel; clearing a route invalidates pending streaming",function()
    local t=context({route={{170,0,0}},streamHang=true})
    t.advance(1);near(t.root.Position.X,0)
    t.advance(1);assert(t.root.Position.X>0)
    t=context({route={{170,0,0}},streamHang=true})
    t.advance(0.5);t.callbacks.EH_TrinketExplore(false);t.advance(5)
    near(t.root.Position.X,0);equal(#t.tweens,0)
end)
test("a slow trip longer than the pickup timeout still reaches and attempts the loot",function()
    local t=context({farm=true})
    local target={Name="Test trinket",Parent=t.drops,Part={Position=Vector3.new(1700,0,0)}}
    t.drops.children={target}
    t.advance(16);equal(t.H.State.CurrentTarget,target);equal(t.pickups,0)
    assert(t.root.Position.X>1200 and t.root.Position.X<1700)
    t.advance(4.2);assert(t.pickups>0)
end)
test("explicit Fly mode continues to move incrementally without TweenService",function()
    local t=context({mode="Fly"})
    t.heartbeat:Connect(function(dt) t.H.FarmMovement.MoveTo(Vector3.new(170,0,0),nil,"loot",dt) end)
    t.advance(1);near(t.root.Position.X,85);equal(#t.tweens,0)
end)
test("segmented tween pauses between short legs and completes without a final pause",function()
    local t=context({segmented=true});local m=t.H.FarmMovement
    equal(t.H.Config.FarmTweenSegmentLength,20);near(t.H.Config.FarmTweenPauseSeconds,0.2)
    t.H.Config.FarmTweenSpeed=100
    local dest=Vector3.new(60,0,0);local arrived=false;local previousX=0
    m.MoveTo(dest,nil,"loot")
    t.heartbeat:Connect(function(dt)
        assert(t.root.Position.X-previousX<=100*dt+0.01)
        previousX=t.root.Position.X
        arrived=m.MoveTo(dest,nil,"loot")
    end)
    near(t.tweens[1].Info.Time,0.2);near(t.tweens[1].Goal.Position.X,20)
    t.advance(0.25);near(t.root.Position.X,20);equal(#t.tweens,1)
    assert(m.Active.PauseUntil>t.now);equal(arrived,false)
    t.advance(0.1);near(t.root.Position.X,20);equal(#t.tweens,1)
    t.advance(0.14);equal(#t.tweens,2);assert(t.root.Position.X>20 and t.root.Position.X<40)
    t.advance(1);near(t.root.Position.X,60);equal(#t.tweens,3)
    equal(arrived,true);equal(m.IsActive(),false)
end)
test("pause, death and unload during a segment break cannot trigger a delayed restart",function()
    for _,action in ipairs({"pause","death","unload"}) do
        local t=context({segmented=true});local m=t.H.FarmMovement
        t.H.Config.FarmTweenSpeed=100
        local dest=Vector3.new(100,0,0)
        m.MoveTo(dest,nil,"loot")
        t.heartbeat:Connect(function() m.MoveTo(dest,nil,"loot") end)
        t.advance(0.25);assert(m.Active.PauseUntil>t.now)
        if action=="pause" then t.H.State.Running=false
        elseif action=="death" then t.hum.Health=0
        else t.H:Unload() end
        t.advance(1);near(t.root.Position.X,20);equal(#t.tweens,1);equal(m.IsActive(),false)
    end
end)
test("position changes during a break are respected by the next segment",function()
    local t=context({segmented=true});local m=t.H.FarmMovement
    t.H.Config.FarmTweenSpeed=100
    local dest=Vector3.new(100,0,0)
    m.MoveTo(dest,nil,"loot")
    t.heartbeat:Connect(function() m.MoveTo(dest,nil,"loot") end)
    t.advance(0.25);near(t.root.Position.X,20)
    t.root.CFrame=CFrame.new(Vector3.new(5,0,0))
    t.advance(0.1);near(t.root.Position.X,5);equal(#t.tweens,1)
    t.advance(0.14);equal(#t.tweens,2)
    near(t.tweens[2].From.X,5);near(t.tweens[2].Goal.Position.X,25)
end)
test("retargeting during a break abandons the old destination",function()
    local t=context({segmented=true});local m=t.H.FarmMovement
    t.H.Config.FarmTweenSpeed=100
    m.MoveTo(Vector3.new(100,0,0),nil,"loot");t.advance(0.25)
    assert(m.Active.PauseUntil>t.now)
    m.MoveTo(Vector3.new(-20,0,0),nil,"loot")
    equal(t.tweens[1].Cancelled,true);equal(#t.tweens,2)
    near(t.tweens[2].Goal.Position.X,0)
    t.advance(0.1);near(t.root.Position.X,10)
end)
test("an intermediate pause never starts the route loot wait",function()
    local t=context({route={{40,0,0}},segmented=true})
    t.H.Config.FarmTweenSpeed=100;t.H.Config.FarmTweenPauseSeconds=0.5
    t.advance(0.6);near(t.root.Position.X,20)
    equal(t.H.GetTrinketRouteStatus().Remaining,0);equal(t.hops,0)
    t.advance(0.6);near(t.root.Position.X,40)
    assert(t.H.GetTrinketRouteStatus().Remaining>1);equal(t.hops,0)
    t.advance(2);equal(t.hops,1)
end)
for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2]);assert(ok,entry[1].."\n"..tostring(err));output("PASS "..entry[1])
end
output(#tests.." farm movement tests passed (simulated services)")

print = output
