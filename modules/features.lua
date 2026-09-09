return function(H)
    local F = {Loading = false, Context = nil, Generation = 0}
    H.Features = F
    F.PinnedRepo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/88cb7baf859ab6e44109be8258c98e43f35978d5"

    function F.Close()
        F.Generation = F.Generation + 1
        local ctx = F.Context
        F.Context = nil
        if ctx and ctx.CloseExtras then ctx.CloseExtras() end
    end

    function F.Load()
        if F.Loading or H.State.Unloaded then return false end
        if F.Context and not F.Context.State.Unloaded then return true end
        F.Loading = true
        local generation = F.Generation
        task.spawn(function()
            local ok, err = pcall(function()
                local source = game:HttpGet(H.Repo .. "modules/extras_unified_loader.lua?v=" .. tostring(os.time()) .. "-" .. tostring(math.random(100000,999999)))
                if H.State.Unloaded or generation ~= F.Generation then return end
                local fn, compileError = loadstring(source, "EndHub Feature Bundle")
                assert(fn, compileError)
                local init = fn()
                assert(type(init) == "function", "invalid feature bundle loader")
                local ctx = init(H, F.PinnedRepo)
                if H.State.Unloaded or generation ~= F.Generation then
                    if ctx and ctx.CloseExtras then ctx.CloseExtras() end
                    return
                end
                F.Context = ctx
            end)
            F.Loading = false
            if not ok then warn("[EndHub Features] " .. tostring(err)) end
        end)
        return true
    end
end
