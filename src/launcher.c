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

#include "openbuslua.h"
#include "extralibraries.h"




static int l_setlogpath (lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  if (openbuslua_setlogpath(path) != LUA_OK) {
    luaL_error(L, "unable to set log path");
  }
  return 0;
}


static int pmain (lua_State *L) {
  char **argv = (char **)lua_touserdata(L, 2);
  int debugmode = argv[0] && argv[1] && strcmp(argv[1], "DEBUG") == 0;
  int status;
  luapreload_extralibraries(L);
#ifdef OPENBUS_CODEREV
  lua_pushliteral(L, OPENBUS_CODEREV);
  lua_setglobal(L, "OPENBUS_CODEREV");
#endif
  status = openbuslua_init(L, 1, debugmode);
  if (status == LUA_OK) {
    lua_pushliteral(L, OPENBUS_PROGNAME);
    lua_setglobal(L, "OPENBUS_PROGNAME");
    lua_pushstring(L, OPENBUS_MAIN);
    lua_setglobal(L, "OPENBUS_MAIN");
    lua_pushstring(L, argv[0]);
    lua_setglobal(L, "OPENBUS_PROGPATH");
    lua_pushcfunction(L, l_setlogpath);
    lua_setglobal(L, "OPENBUS_SETLOGPATH");
    lua_getglobal(L, "require");
    lua_pushstring(L, OPENBUS_MAIN);
    status = lua_pcall(L, 1, 1, 0);
    if (status == LUA_OK) {
      int narg;
      if (debugmode) ++argv;
      narg = openbuslua_pushargs(L, argv);  /* collect arguments */
      status = openbuslua_call(L, narg+1, 1);
      if ( (status == LUA_OK) && lua_isnumber(L, -1) ) return 1;
    }
  }
  openbuslua_report(L, status);
  lua_pushinteger(L, status == LUA_OK ? 0 : EXIT_FAILURE);
  return 1;
}


int main (int argc, char **argv) {
  int status, result = EXIT_FAILURE;
  lua_State *L = luaL_newstate();  /* create state */
  if (L == NULL) {
    openbuslua_logmessage(argv[0], "cannot create Lua state: not enough memory");
  } else {
    /* call 'pmain' in protected mode */
    lua_pushcfunction(L, &pmain);
    lua_pushinteger(L, argc);  /* 1st argument */
    lua_pushlightuserdata(L, argv); /* 2nd argument */
    status = lua_pcall(L, 2, 1, 0);
    if (status == LUA_OK) {
      result = (int)lua_tointeger(L, -1);  /* get result */
    } else {
      const char *msg = (lua_type(L, -1) == LUA_TSTRING) ? lua_tostring(L, -1)
                                                         : NULL;
      if (msg == NULL) msg = "(error object is not a string)";
      openbuslua_logmessage(argv[0], msg);
      lua_pop(L, 1);
    }
    lua_close(L);
    openbuslua_setlogpath(NULL);
  }
  return result;
}

