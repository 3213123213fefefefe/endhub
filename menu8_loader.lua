local source = game:HttpGet("https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/work_loader.lua?v=" .. tostring(os.time()))
local fn, err = loadstring(source)
assert(fn, err)
return fn()
