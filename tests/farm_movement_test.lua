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
    local t = {now = 0, jobs = {}, tweens = {}, hops = 0, pickups = 0, callbacks = {}, raycasts = {}, floorY = options.groundY}
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
    CFrame = {new = function(pos) return setmetatable({Position=pos,Rotation={},LookVector=Vector3.new(0,0,-1)},frame) end}
    CFrame.lookAt = CFrame.new
    TweenInfo = {new = function(duration, easing) return {Time=duration,EasingStyle=easing} end}
    Enum = {EasingStyle={Linear="Linear"},PlaybackState={Completed="Completed",Cancelled="Cancelled"},
        HumanoidRigType={R6="R6",R15="R15"},RaycastFilterType={Exclude="Exclude"}}
    RaycastParams = {new = function() return {} end}
    workspace = {}
    function workspace:Raycast(origin, direction, params)
        t.raycasts[#t.raycasts+1] = {Origin=origin,Direction=direction,Params=params}
        if options.raycastError then error("ground query unavailable") end
        if t.floorY and t.floorY <= origin.Y and t.floorY >= origin.Y + direction.Y then
            return {Position=Vector3.new(origin.X,t.floorY,origin.Z),Normal=Vector3.new(0,options.floorNormalY or 1,0)}
        end
    end
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
    local heartbeat, added, stepped = signal(),signal(),signal()
    local root = setmetatable({Parent=true,_frame=CFrame.new(Vector3.new(0,options.startY or 0,0)),
        Size=Vector3.new(2,2,1),CollisionGroup="Default",CanCollide=true}, {
        __index=function(r,k)
            if k=="Position" then return r._frame.Position end
            if k=="CFrame" then return r._frame end
        end,
        __newindex=function(r,k,v) if k=="CFrame" then rawset(r,"_frame",v) else rawset(r,k,v) end end,
    })
    function root:IsA(kind) return kind=="BasePart" end
    local hum = {Health=100,HipHeight=options.r6 and 0 or 2,RigType=options.r6 and "R6" or "R15"}
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
    local leg={Size=Vector3.new(1,options.legHeight or 2,1)}
    local character={DescendantAdded=signal(),DescendantRemoving=signal()}
    function character:GetDescendants() return {root} end
    function character:FindFirstChild(name) if name=="Left Leg" then return leg end end
    root.Parent=character
    local player={Character=character,CharacterAdded=added}
    function player:RequestStreamAroundAsync()
        if options.streamHang then task.wait(1000) end
    end
    local drops={children={},ChildRemoved=signal()}
    function drops:GetChildren() return self.children end
    local H={Config={FarmMoveMode=options.mode or "TP",FarmTweenSpeed=85,FarmFlySpeed=85,
        FarmTweenPauseSeconds=0,BotNoclip=true,
        AutoPickup=true,BackgroundPickup=false,PickupDistance=7,TargetHeight=3,TargetTimeout=15,PickupInterval=0.3},
        State={Ready=true,Running=true,Unloaded=false,StartedAt=0,Collected=0,LastPickup=0,FarmSellPhase="FARM"},
        Connections={},OriginalCollision={},S={RunService={Heartbeat=heartbeat,Stepped=stepped},Player=player},Core={}}
    function H:Unload()
        self.State.Unloaded=true
        for _,c in ipairs(self.Connections) do c:Disconnect() end
    end
    H.Core={Root=function() return t.root end,Humanoid=function() return hum end,Character=function() return character end,
        Noclip=function(active)
            t.noclip=active
            if active then
                if H.OriginalCollision[root]==nil then H.OriginalCollision[root]=root.CanCollide end
                root.CanCollide=false
            else
                for part,old in pairs(H.OriginalCollision) do part.CanCollide=old end
                table.clear(H.OriginalCollision)
            end
        end,DropsFolder=function() return drops end,
        IsTrinketDrop=function(obj) return obj and obj.Parent==drops end,
        DropPart=function(obj) return obj and obj.Part end,
        PressKey=function() t.pickups=t.pickups+1 return true end,
        Connect=function(s,fn) local c=s:Connect(fn) H.Connections[#H.Connections+1]=c return c end,
        Teleport=function() error("automated movement used direct teleport") end}
    t.H,t.root,t.hum,t.player,t.heartbeat,t.drops=H,root,hum,player,heartbeat,drops
    if options.segmented then H.Config.FarmTweenPauseSeconds = nil end
    assert(loadfile("modules/farm_movement.lua"))()(H)
    if options.noclipPatches then
        assert(loadfile("modules/fps_patch.lua"))()(H)
        assert(loadfile("modules/noclip_strength_patch.lua"))()(H)
    end
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
            stepped:Fire(t.now,dt)
            for _,tw in ipairs(t.tweens) do
                if tw.Playing then
                    local alpha=math.min(1,(t.now-tw.Started)/tw.Info.Time)
                    tw.Root.CFrame=CFrame.new(tw.From+(tw.Goal.Position-tw.From)*alpha)
                    if alpha>=1 then tw.Playing=false tw.FinishedAt=t.now tw.Completed:Fire("Completed") end
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
test("ground pauses land first, keep floor collision, then smoothly resume travel height",function()
    local t=context({segmented=true,groundY=0,startY=23,noclipPatches=true});local m=t.H.FarmMovement
    t.H.Config.FarmTweenSpeed=100
    equal(t.H.Config.FarmTweenGroundPauses,true)
    local dest=Vector3.new(60,23,0);local arrived=false
    m.MoveTo(dest,nil,"route")
    t.heartbeat:Connect(function()
        -- Other automation callers must not turn noclip back on while grounded.
        t.H.Core.Noclip(true)
        arrived=m.MoveTo(dest,nil,"route")
    end)
    t.advance(0.25);equal(m.Active.Phase,"landing");equal(m.Active.PauseUntil,nil)
    equal(t.root.CanCollide,false);near(t.tweens[2].Goal.Position.Y,3)
    near(t.tweens[2].Info.Time,0.2);equal(arrived,false)
    local params=t.raycasts[1].Params
    equal(params.FilterDescendantsInstances[1],t.player.Character)
    equal(params.FilterType,"Exclude");equal(params.RespectCanCollide,true);equal(params.IgnoreWater,true)
    t.advance(0.25);near(t.root.Position.Y,3);near(t.root.Position.X,20)
    equal(m.IsGroundedPause(),true);equal(t.root.CanCollide,true)
    near(m.Active.PauseUntil,t.tweens[2].FinishedAt+0.2)
    t.root.AssemblyLinearVelocity=Vector3.new(4,-1,4)
    t.advance(0.1);near(t.root.Position.Y,3);equal(t.root.CanCollide,true)
    near(t.root.AssemblyLinearVelocity.Y,-1);near(t.root.AssemblyLinearVelocity.X,0)
    t.advance(0.15);equal(m.Active.Phase,"resume");equal(t.root.CanCollide,false)
    near(t.tweens[3].From.Y,3);near(t.tweens[3].Goal.Position.Y,23)
    t.advance(2);near(t.root.Position.X,60);near(t.root.Position.Y,23)
    equal(arrived,true);equal(m.IsActive(),false)
end)
test("R6 ground clearance includes scaled legs and R15 uses hip height",function()
    for _,r6 in ipairs({false,true}) do
        local t=context({segmented=true,groundY=10,startY=30,r6=r6,legHeight=4});local m=t.H.FarmMovement
        t.H.Config.FarmTweenSpeed=100
        m.MoveTo(Vector3.new(100,30,0),nil,"loot")
        t.advance(0.5)
        near(t.root.Position.Y,r6 and 15 or 13);equal(m.IsGroundedPause(),true)
    end
end)
test("missing, steep or unavailable floors keep an airborne pause without a descent",function()
    for _,options in ipairs({{}, {groundY=-1000}, {groundY=0,floorNormalY=0.1}, {raycastError=true}}) do
        options.segmented=true;options.startY=23
        local t=context(options);local m=t.H.FarmMovement;t.H.Config.FarmTweenSpeed=100
        m.MoveTo(Vector3.new(100,23,0),nil,"loot");t.advance(0.25)
        equal(#t.tweens,1);near(t.root.Position.Y,23)
        equal(m.IsGroundedPause(),false);assert(m.Active.PauseUntil>t.now)
    end
end)
test("disappearing ground is rechecked before enabling floor collision",function()
    local t=context({segmented=true,groundY=0,startY=23});local m=t.H.FarmMovement
    t.H.Config.FarmTweenSpeed=100
    m.MoveTo(Vector3.new(100,23,0),nil,"loot");t.advance(0.25)
    equal(m.Active.Phase,"landing");t.floorY=nil;t.advance(0.25)
    equal(m.IsGroundedPause(),false);equal(t.noclip,true);assert(m.Active.PauseUntil>t.now)
end)
test("stop, death, replacement, unload and retarget cancel every ground detour phase",function()
    for _,when in ipairs({0.25,0.5,0.75}) do
        for _,action in ipairs({"stop","death","character","unload","retarget"}) do
            local t=context({segmented=true,groundY=0,startY=23});local m=t.H.FarmMovement
            t.H.Config.FarmTweenSpeed=100
            local dest=Vector3.new(100,23,0);local driving=true
            m.MoveTo(dest,nil,"loot")
            t.heartbeat:Connect(function() if driving then m.MoveTo(dest,nil,"loot") end end)
            t.advance(when);local old=m.Active;local oldTween=old.Tween
            if action=="stop" then t.H.State.Running=false
            elseif action=="death" then t.hum.Health=0
            elseif action=="character" then driving=false;t.player.CharacterAdded:Fire()
            elseif action=="unload" then t.H:Unload()
            else driving=false;m.MoveTo(Vector3.new(-100,23,0),nil,"loot")
            end
            t.advance(0.05);assert(m.Active~=old);equal(oldTween.Cancelled,true)
            if action=="retarget" then m.Cancel() end
            local count=#t.tweens;local pos=t.root.Position
            t.advance(2);equal(#t.tweens,count);near((t.root.Position-pos).Magnitude,0)
        end
    end
end)
test("ground pauses respect a displaced position and disabling the option resumes immediately",function()
    for _,disable in ipairs({false,true}) do
        local t=context({segmented=true,groundY=0,startY=23});local m=t.H.FarmMovement
        t.H.Config.FarmTweenSpeed=100
        local dest=Vector3.new(100,23,0)
        m.MoveTo(dest,nil,"loot");t.advance(0.5);equal(m.IsGroundedPause(),true)
        if disable then
            t.H.Config.FarmTweenGroundPauses=false
        else
            t.root.CFrame=CFrame.new(Vector3.new(5,3,0))
            t.advance(0.3)
        end
        m.MoveTo(dest,nil,"loot")
        equal(m.Active.Phase,"travel");near(t.tweens[#t.tweens].From.X,disable and 20 or 5)
        near(t.tweens[#t.tweens].From.Y,3)
    end
end)
test("continuous Tween, disabled ground pauses and Fly never probe for a floor",function()
    for _,mode in ipairs({"continuous","off","Fly"}) do
        local t=context({segmented=mode~="continuous",mode=mode=="Fly" and "Fly" or "Tween",groundY=0,startY=23})
        t.H.Config.FarmTweenSpeed=100
        if mode=="off" then t.H.Config.FarmTweenGroundPauses=false end
        t.H.FarmMovement.MoveTo(Vector3.new(100,23,0),nil,"loot");t.advance(0.5)
        equal(#t.raycasts,0)
    end
end)
test("ground detours do not advance elevated routes or start their loot wait",function()
    local t=context({route={{40,23,0}},segmented=true,groundY=0,startY=23})
    t.H.Config.FarmTweenSpeed=100
    t.advance(0.6);near(t.root.Position.X,20);near(t.root.Position.Y,3)
    equal(t.H.GetTrinketRouteStatus().Remaining,0);equal(t.hops,0)
    t.advance(0.8);near(t.root.Position.X,40);near(t.root.Position.Y,23)
    assert(t.H.GetTrinketRouteStatus().Remaining>1);equal(t.hops,0)
    t.advance(2);equal(t.hops,1)
end)
for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2]);assert(ok,entry[1].."\n"..tostring(err));output("PASS "..entry[1])
end
output(#tests.." farm movement tests passed (simulated services)")

print = output
