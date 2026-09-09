-- EndHub loader
-- Loads the current Work build plus the first-screen menu patch.
local nonce = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local url = "https://raw.githubusercontent.com/3213123213fefefefe/endhub/main/menu8_loader.lua?v=" .. nonce
local source = game:HttpGet(url)
local fn, err = loadstring(source)
if not fn then
    error("[EndHub Loader] compile error: " .. tostring(err))
end
return fn()
