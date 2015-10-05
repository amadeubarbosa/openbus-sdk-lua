#ifndef openbuslua_h
#define openbuslua_h

#include "lua.h"

LUALIB_API int openbuslua_init (lua_State *L, int interactive, int debugmode);
LUALIB_API int openbuslua_call (lua_State *L, int narg, int nres);
LUALIB_API int openbuslua_dostring (lua_State *L, const char *s, const char *name);
LUALIB_API int openbuslua_pushargs (lua_State *L, char **argv);
LUALIB_API void openbuslua_logmessage (const char *pname, const char *msg);
LUALIB_API int openbuslua_report (lua_State *L, int status);
LUALIB_API int openbuslua_setlogpath (const char *path);

#endif
