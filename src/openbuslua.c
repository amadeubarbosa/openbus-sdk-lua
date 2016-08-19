/*
** $Id: lua.c,v 1.206 2012/09/29 20:07:06 roberto Exp $
** Lua stand-alone interpreter
** See Copyright Notice in lua.h
*/


#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
#include <compat-5.2.h>
#include <luacompat52.h>
#endif

#include <luuid.h>
#include <lce.h>
#include <luasec.h>
#include <lfs.h>
#include <luavararg.h>
#include <luastruct.h>
#include <luasocket.h>
#include <loop.h>
#include <luatuple.h>
#include <luacothread.h>
#include <luaidl.h>
#include <oil.h>
#include <luascs.h>
#include <luaopenbus.h>
#include <lsqlite3.h>




static lua_State *globalL = NULL;

static char *logpath = NULL;

static const char *callerchunk =
#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
" require 'compat52'"
#endif
" local _G = require '_G'"
" local error = _G.error"
" local tostring = _G.tostring"

" local coroutine = require 'coroutine'"
" local newthread = coroutine.create"

" local debug = require 'debug'"
" local traceback = debug.traceback"

" local cothread = require 'cothread'"
" local step = cothread.step"
" local run = cothread.run"

" local log = require 'openbus.util.logger'"

" function cothread.error(thread, errmsg, ...)"
"   errmsg = traceback(thread, tostring(errmsg))"
"   log:unexpected(errmsg)"
"   error(errmsg)"
" end"

" return function(f, ...)"
"   return run(step(newthread(f), ...)) or OPENBUS_EXITCODE"
" end";



static void lstop (lua_State *L, lua_Debug *ar) {
  (void)ar;  /* unused arg. */
  lua_sethook(L, NULL, 0, 0);
  luaL_error(L, "interrupted!");
}


static void laction (int i) {
  signal(i, SIG_DFL); /* if another SIGINT happens before lstop,
                         terminate process (default action) */
  lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}


static int traceback (lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg)
    luaL_traceback(L, L, msg, 1);
  else if (!lua_isnoneornil(L, 1)) {  /* is there an error object? */
    if (!luaL_callmeta(L, 1, "__tostring"))  /* try its 'tostring' metamethod */
      lua_pushliteral(L, "(no error message)");
  }
  return 1;
}


LUALIB_API int openbuslua_setlogpath (const char *path) {
  if (logpath) free(logpath);
  if (path) {
    size_t len = strlen(path);
    logpath = (char *)malloc((len)*sizeof(char));
    if (logpath) strncpy(logpath, path, len);
    return logpath ? LUA_OK : LUA_ERRMEM;
  }
  return LUA_OK;
}


LUALIB_API void openbuslua_logmessage (const char *pname, const char *msg) {
  FILE *out = NULL;
  if (logpath) out = fopen(logpath, "a");
  if (out == NULL) out = stderr;
  if (pname) fprintf(out, "%s: ", pname);
  fprintf(out, "%s\n", msg);
  fflush(out);
  if (out != stderr) fclose(out);
}


LUALIB_API int openbuslua_report (lua_State *L, int status) {
  if (status != LUA_OK && !lua_isnil(L, -1)) {
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL) msg = "(error object is not a string)";
    openbuslua_logmessage(NULL, msg);
    lua_pop(L, 1);
    /* force a complete garbage collection in case of errors */
    lua_gc(L, LUA_GCCOLLECT, 0);
  }
  return status;
}


LUALIB_API int openbuslua_call (lua_State *L, int narg, int nres) {
  int status;
  int base = lua_gettop(L) - narg;  /* function index */
  lua_pushcfunction(L, traceback);  /* push traceback function */
  lua_insert(L, base);  /* put it under chunk and args */
  globalL = L;  /* to be available to 'laction' */
  signal(SIGINT, laction);
  status = lua_pcall(L, narg, nres, base);
  signal(SIGINT, SIG_DFL);
  lua_remove(L, base);  /* remove traceback function */
  return status;
}


LUALIB_API int openbuslua_dostring (lua_State *L, const char *s, const char *name) {
  int status = luaL_loadbuffer(L, s, strlen(s), name);
  if (status == LUA_OK) status = openbuslua_call(L, 0, LUA_MULTRET);
  return status;
}


LUALIB_API int openbuslua_pushargs (lua_State *L, char **argv) {
  int narg;
  int i;
  int argc = 0;
  while (argv[argc]) argc++;  /* count total number of arguments */
  narg = argc-1;  /* number of arguments to the script */
  luaL_checkstack(L, narg, "too many arguments to script");
  for (i=1; i < argc; i++) lua_pushstring(L, argv[i]);
  return narg;
}


LUALIB_API int openbuslua_init (lua_State *L, int interactive, int debugmode) {
  int status = LUA_OK;
  /* open standard libraries */
  luaL_checkversion(L);
  lua_gc(L, LUA_GCSTOP, 0);  /* stop collector during initialization */
  luaL_openlibs(L);  /* open libraries */
  lua_gc(L, LUA_GCRESTART, 0);

  /* export to Lua defined C constants */
  if (debugmode) {
    lua_pushboolean(L, 1);
    lua_setfield(L, LUA_REGISTRYINDEX, "OPENBUS_DEBUG");
    status = openbuslua_dostring(L,
      " if OPENBUS_CODEREV ~= nil then"
      "   OPENBUS_CODEREV = OPENBUS_CODEREV..'-DEBUG'"
      " end"
      " table.insert(package.searchers, (table.remove(package.searchers, 1)))",
      "SET_DEBUG");
  }
  
  /* open extended libraries */
  if (status == LUA_OK) {
    /* preload libraries and global variables */
#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
    luapreload_luacompat52(L);
#endif
    /* preload binded C libraries */
#if defined(LUA_VERSION_NUM) && LUA_VERSION_NUM > 501
    luaL_getsubtable(L, LUA_REGISTRYINDEX, "_PRELOAD");
#else
    luaL_findtable(L, LUA_GLOBALSINDEX, "package.preload", 1);
#endif
    lua_pushcfunction(L,luaopen_uuid);lua_setfield(L,-2,"uuid");
    lua_pushcfunction(L,luaopen_lfs);lua_setfield(L,-2,"lfs");
    lua_pushcfunction(L,luaopen_vararg);lua_setfield(L,-2,"vararg");
    lua_pushcfunction(L,luaopen_struct);lua_setfield(L,-2,"struct");
    lua_pushcfunction(L,luaopen_socket_core);lua_setfield(L,-2,"socket.core");
    lua_pushcfunction(L,luaopen_lsqlite3);lua_setfield(L,-2,"lsqlite3");
    lua_pop(L, 1);  /* pop 'package.preload' table */
    /* preload other C libraries */
    luapreload_lce(L);
    luapreload_luasec(L);
    /* preload script libraries */
    luapreload_loop(L);
    luapreload_luatuple(L);
    luapreload_luacothread(L);
    luapreload_luaidl(L);
    luapreload_oil(L);
    luapreload_luascs(L);
    luapreload_luaopenbus(L);
    /* push main module executor */
    status = openbuslua_dostring(L, callerchunk, "MAIN_THREAD");
    if ((status == LUA_OK) && interactive) {
      lua_pushvalue(L, -1);
      lua_getglobal(L, "require");
      lua_pushstring(L, "openbus.console.costdin");
      status = lua_pcall(L, 1, 1, 0);
      if (status == LUA_OK) {
        status = openbuslua_call(L, 1, 0);
      }
    }
  }
  return status;
}
