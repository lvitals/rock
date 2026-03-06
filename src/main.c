#include <stdio.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

int main(int argc, char *argv[]) {
    lua_State *L = luaL_newstate();
    if (L == NULL) {
        fprintf(stderr, "Error: Could not initialize Lua state.\n");
        return 1;
    }

    luaL_openlibs(L);

    // Push CLI arguments to Lua 'arg' table
    lua_createtable(L, argc, 0);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    // Load main logic with path discovery
    const char *bootstrap =
        "local function try_require()\n"
        "    local ok, m = pcall(require, 'lua.rock.init')\n"
        "    if ok then return true end\n"
        "    local home = os.getenv('HOME')\n"
        "    local rock_root = os.getenv('ROCK_ROOT') or (home and home .. '/.rock')\n"
        "    if rock_root then\n"
        "        package.path = rock_root .. '/?.lua;' .. rock_root .. '/?/init.lua;' .. package.path\n"
        "        ok, m = pcall(require, 'lua.rock.init')\n"
        "        if ok then return true end\n"
        "    end\n"
        "    package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path\n"
        "    return pcall(require, 'lua.rock.init')\n"
        "end\n"
        "if not try_require() then\n"
        "    io.stderr:write('Rock Error: Could not find lua.rock.init\\n')\n"
        "    os.exit(1)\n"
        "end";

    if (luaL_dostring(L, bootstrap)) {
        fprintf(stderr, "Fatal: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
