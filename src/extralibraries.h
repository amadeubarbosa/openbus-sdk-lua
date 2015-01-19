#ifndef EXTRALIBRARIES_H
#define EXTRALIBRARIES_H

#include "lua.h"

extern const char const* OPENBUS_MAIN;

void luapreload_extralibraries(lua_State*);

#endif
