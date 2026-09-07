-- EndHub loader
local url = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/EndHub.lua"
local source = game:HttpGet(url)
local fn, err = loadstring(source)
if not fn then error("[EndHub Loader] compile error: " .. tostring(err)) end
return fn()
