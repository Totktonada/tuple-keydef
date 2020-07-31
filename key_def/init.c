#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <tarantool/module.h>

extern char key_def_lua[];

/**
 * Execute key_def.lua when key_def.so is loaded.
 */
__attribute__((constructor)) static void
setup(void)
{
	struct lua_State *L = luaT_state();
	int top = lua_gettop(L);

	const char *modname = "key_def";
	const char *modsrc = key_def_lua;
	const char *modfile = lua_pushfstring(L,
		"@key_def/builtin/%s.lua", modname);
	if (luaL_loadbuffer(L, modsrc, strlen(modsrc), modfile)) {
#if 0
		panic("Error loading Lua module %s...: %s",
		      modname, lua_tostring(L, -1));
#endif
		/* XXX: What to do here? */
		lua_settop(L, top);
		return;
	}
	lua_pushstring(L, modname);
	lua_call(L, 1, 1);
	/* Ignore Lua return value. */

	lua_settop(L, top);
}
