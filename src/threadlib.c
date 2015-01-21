#include <lua.h>
#include <lauxlib.h>

#include <openbuslua.h>

#if defined(_WIN32)

#include <errno.h>
#include <process.h>

int prompt_newthread(void (__cdecl *func) (void *), void *data) {
  uintptr_t res = _beginthread(func, 0, data);
  if (res == -1L) return errno;
	return 0;
}

const char *prompt_errormessage(int code) {
  switch (code) {
    case EAGAIN: return "too many threads";
    case EINVAL: return "stack size is incorrect";
    case EACCES: return "insufficient resources";    
  }
	return "unexpected error";
}

void OpenBusLuaThread (void *data)
{
	lua_State *L = (lua_State *)data;
	int status = openbuslua_call(L, 1, 0);
	openbuslua_report(L, status);
}

#else

#include <pthread.h>
#include <errno.h>
#include <string.h>

int prompt_newthread(void *(*func) (void *), void *data) {
	pthread_t thread;
	int res = pthread_create(&thread, NULL, func, data);
	if (res) return errno;
	return 0;
}

const char *prompt_errormessage(int code) {
	return strerror(code);
}

static void *OpenBusLuaThread (void *data)
{
	lua_State *L = (lua_State *)data;
	int status = openbuslua_call(L, 1, 0);
	openbuslua_report(L, status);
	pthread_exit(NULL);
}

#endif

#include "openbuslua.h"


static void copyPreload (lua_State *from, lua_State *to)
{
	/* table is in the stack at index 't' */
#if defined(LUA_VERSION_NUM) && LUA_VERSION_NUM > 501
	luaL_getsubtable(from, LUA_REGISTRYINDEX, "_PRELOAD");
	luaL_getsubtable(to, LUA_REGISTRYINDEX, "_PRELOAD");
#else
	luaL_findtable(from, LUA_GLOBALSINDEX, "package.preload", 1);
	luaL_findtable(to, LUA_GLOBALSINDEX, "package.preload", 1);
#endif
	lua_pushnil(from);  /* first key */
	while (lua_next(from, -2) != 0) {
		const char *name = lua_tostring(from, -2);
		lua_CFunction func = lua_tocfunction(from, -1);
		lua_getfield(to, -1, name);
		if (lua_isnil(to, -1) && name != NULL && func != NULL) {
			lua_pushcfunction(to, func);
			lua_setfield(to, -3, name);
		}
		lua_pop(from, 1);  /* pop value and leave key for next iteration */
		lua_pop(to, 1);  /* pop value of '_PRELOAD[modname]' */
	}
	lua_pop(from, 1);  /* pop '_PRELOAD' table */
	lua_pop(to, 1);  /* pop '_PRELOAD' table */
}

static int l_spawn (lua_State *L)
{
	int status = LUA_OK;
	size_t codelen;
	const char *code = luaL_checklstring(L, 1, &codelen);
	lua_State *newL = luaL_newstate();  /* create state */
	if (newL == NULL) luaL_error(L, "not enough memory");
	lua_getfield(L, LUA_REGISTRYINDEX, "OPENBUS_DEBUG");
	status = openbuslua_init(newL, 0, !lua_isnil(L, -1));
	if (status == LUA_OK) {
		copyPreload(L, newL);
		status = luaL_loadbuffer(newL, code, codelen, code);
		if (status == LUA_OK) {
			int res = prompt_newthread(OpenBusLuaThread, newL);
			if (res) {
				const char *errmsg = prompt_errormessage(errno);
				lua_close(newL);
				luaL_error(L, "unable to start thread (error=%s)", errmsg);
			}
		}
	}
	if (status != LUA_OK && !lua_isnil(newL, -1)) {
		const char *msg = lua_tostring(newL, -1);
		if (msg == NULL) msg = "(error object is not a string)";
		lua_pushstring(L, msg);
		lua_close(newL);
		lua_error(L);
	}
	return 0;
}

static const luaL_Reg funcs[] = {
  {"spawn", l_spawn},
  {NULL, NULL}
};


LUAMOD_API int luaopen_openbus_util_thread (lua_State *L) {
	luaL_newlib(L, funcs);
	return 1;
}
