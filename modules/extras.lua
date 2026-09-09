return function(H)
    local X = {Loading = false, Context = nil, Generation = 0}
    H.Extras = X
    -- Pinned optional bundle: the main loader never fetches these modules.
    X.URL = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/88cb7baf859ab6e44109be8258c98e43f35978d5/loader.lua"
    function X.Close()
        X.Generation = X.Generation + 1
        local ctx = X.Context
        X.Context = nil
        if ctx and ctx.CloseExtras then ctx.CloseExtras() end
    end
    function X.Open()
        if X.Loading or H.State.Unloaded then return end
        if X.Context and not X.Context.State.Unloaded then
            local lib = X.Context.UI.Library
            if not lib.Unloaded then lib:Toggle(true) return end
            X.Close()
        end
        X.Loading = true
        local generation = X.Generation
        task.spawn(function()
            local ctx
            local ok, err = pcall(function()
                local source = game:HttpGet(X.URL)
                if H.State.Unloaded or generation ~= X.Generation then return end
                local fn, compileError = loadstring(source, "EndHub Extras")
                assert(fn, compileError)
                ctx = fn()(H, X.URL:match("^(.*)/loader.lua$"))
                if H.State.Unloaded or generation ~= X.Generation then ctx.CloseExtras() return end
                X.Context = ctx
            end)
            X.Loading = false
            if not ok then warn("[EndHub Extras] " .. tostring(err)) end
        end)
    end
end
