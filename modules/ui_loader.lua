return function(H)
    local source = game:HttpGet(H.Repo .. "modules/ui.lua?v=" .. tostring(math.random()), true)

    local old = [=[                    local okLib, lib = pcall(fn)
                    if okLib and type(lib) == "table" then
                        return lib, url
                    end
                    lastErr = tostring(lib)]=]

    local new = [=[                    local okLib, lib = pcall(fn)
                    if okLib and type(lib) == "function" then
                        local okInit, initialized = pcall(lib, nil, nil)
                        if okInit then
                            lib = initialized
                        else
                            lastErr = "initializer failed: " .. tostring(initialized)
                        end
                    end

                    if okLib and type(lib) == "table" then
                        return lib, url
                    end

                    if type(lib) ~= "table" then
                        lastErr = "unexpected library result type: " .. typeof(lib) .. " | " .. tostring(lib)
                    end]=]

    local s, e = string.find(source, old, 1, true)
    if not s then
        error("[EndHub] ui compatibility patch target not found")
    end

    source = string.sub(source, 1, s - 1) .. new .. string.sub(source, e + 1)

    local fn, compileErr = loadstring(source)
    if not fn then
        error("[EndHub] patched UI compile failed: " .. tostring(compileErr))
    end

    local init = fn()
    if type(init) ~= "function" then
        error("[EndHub] patched UI returned " .. typeof(init) .. " instead of function")
    end

    init(H)
end
