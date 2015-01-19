#include "extralibraries.h"

#include "lua.h"
#include "lauxlib.h"

#include "luaconsole.h"

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
#include "compat-5.2.h"
#endif

const char const* OPENBUS_MAIN = "openbus.console";

void luapreload_extralibraries(lua_State *L)
{
  luapreload_luaconsole(L);
}
