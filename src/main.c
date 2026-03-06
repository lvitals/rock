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

    // Load main logic
    const char *bootstrap = "require('lua.rock.init')";

    if (luaL_dostring(L, bootstrap)) {
        fprintf(stderr, "Fatal: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
