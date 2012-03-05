#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"


#define BINARY_BITOP(name, op) \
static int name(lua_State *L) \
{ \
  luaL_Buffer b; \
  size_t i, sz, osz; \
  char res[LUAL_BUFFERSIZE]; \
  const char *op1 = luaL_checklstring(L, 1, &sz); \
  const char *op2 = luaL_checklstring(L, 2, &osz); \
  luaL_argcheck(L, sz==osz, 2, "must be the same length of argument #1"); \
  luaL_buffinit(L, &b); \
  while (sz>LUAL_BUFFERSIZE) { \
    for(i=0; i<LUAL_BUFFERSIZE; ++i) res[i] = op1[i] op op2[i]; \
    luaL_addlstring(&b, res, LUAL_BUFFERSIZE); \
    op1 += LUAL_BUFFERSIZE; \
    op2 += LUAL_BUFFERSIZE; \
    sz -= LUAL_BUFFERSIZE; \
  } \
  for(i=0; i<sz; ++i) res[i] = op1[i] op op2[i]; \
  luaL_addlstring(&b, res, sz); \
  luaL_pushresult(&b); \
  return 1; \
}

static int str_not(lua_State *L)
{
  luaL_Buffer b;
  size_t i, sz;
  char res[LUAL_BUFFERSIZE];
  const char *op = luaL_checklstring(L, 1, &sz);
  luaL_buffinit(L, &b);
  while (sz>LUAL_BUFFERSIZE) {
    for(i=0; i<LUAL_BUFFERSIZE; ++i) res[i] = ~op[i];
    luaL_addlstring(&b, res, LUAL_BUFFERSIZE);
    op += LUAL_BUFFERSIZE;
    sz -= LUAL_BUFFERSIZE;
  }
  for(i=0; i<sz; ++i) res[i] = ~op[i];
  luaL_addlstring(&b, res, sz);
  luaL_pushresult(&b);
  return 1;
}

BINARY_BITOP(str_and, &)
BINARY_BITOP(str_or, |)
BINARY_BITOP(str_xor, ^)


static const luaL_Reg strbitlib[] = {
  {"bnot", str_not},
  {"band", str_and},
  {"bor", str_or},
  {"bxor", str_xor},
  {NULL, NULL}
};


LUALIB_API int luaopen_string_bitwise(lua_State *L) {
  luaL_register(L, LUA_STRLIBNAME, strbitlib);
  return 1;
}
