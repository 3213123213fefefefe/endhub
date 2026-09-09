return function(H)
    local X = {Loading = false, Context = nil, Generation = 0}
    H.Extras = X
    X.PinnedRepo = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/88cb7baf859ab6e44109be8258c98e43f35978d5"

    function X.Close()
        X.Generation = X.Generation + 1
        local ctx = X.Context
        X.Context = nil
        if ctx and ctx.CloseExtras then ctx.CloseExtras() end
    end

    function X.Open()
        if X.Loading or H.State.Unloaded then return false end
        if X.Context and not X.Context.State.Unloaded then return true end
        X.Loading = true
        local generation = X.Generation
        task.spawn(function()
            local ok, err = pcall(function()
                local source = game:HttpGet(H.Repo .. "modules/extras_unified_loader.lua?v=" .. tostring(os.time()) .. "-" .. tostring(math.random(100000,999999)))
                if H.State.Unloaded or generation ~= X.Generation then return end
                local fn, compileError = loadstring(source, "EndHub Unified Extras")
                assert(fn, compileError)
                local init = fn()
                assert(type(init) == "function", "invalid unified extras loader")
                local ctx = init(H, X.PinnedRepo)
                if H.State.Unloaded or generation ~= X.Generation then
                    if ctx and ctx.CloseExtras then ctx.CloseExtras() end
                    return
                end
                X.Context = ctx
            end)
            X.Loading = false
            if not ok then warn("[EndHub Extras] " .. tostring(err)) end
        end)
        return true
    end
end
