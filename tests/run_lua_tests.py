"""Run the deterministic Lua suite using a system Lua 5.4 shared library."""
import ctypes
import ctypes.util
import os
from pathlib import Path

os.chdir(Path(__file__).resolve().parents[1])
lib = ctypes.CDLL(ctypes.util.find_library("lua5.4") or "liblua5.4.so.0")
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
lib.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
state = lib.luaL_newstate()
if not state:
    raise SystemExit("Cannot allocate Lua state")
try:
    lib.luaL_openlibs(state)
    paths = list(Path(".").rglob("*.lua"))
    extras = Path("../endhub-extras")
    if extras.is_dir(): paths.extend(extras.rglob("*.lua"))
    for path in paths:
        if lib.luaL_loadfilex(state, str(path).encode(), None):
            raise SystemExit(lib.lua_tolstring(state, -1, None).decode())
        lib.lua_settop(state, 0)
    print(f"Syntax OK: {len(paths)} Lua files", flush=True)
    error = lib.luaL_loadfilex(state, b"tests/server_cycle_test.lua", None)
    if not error:
        error = lib.lua_pcallk(state, 0, 0, 0, 0, None)
    if error:
        raise SystemExit(lib.lua_tolstring(state, -1, None).decode())
    lib.lua_settop(state, 0)
    error = lib.luaL_loadfilex(state, b"tests/trinket_rarity_test.lua", None)
    if not error:
        error = lib.lua_pcallk(state, 0, 0, 0, 0, None)
    if error:
        raise SystemExit(lib.lua_tolstring(state, -1, None).decode())
finally:
    lib.lua_close(state)
