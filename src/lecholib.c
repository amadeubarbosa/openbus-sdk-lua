#include <lua.h>
#include <lauxlib.h>

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM == 501
#include "compat-5.2.h"
#endif

#if defined(_WIN32)

#include <windows.h>

static int getecho(int *active)
{
	HANDLE hstdin = GetStdHandle(STD_INPUT_HANDLE);
	if (hstdin != INVALID_HANDLE_VALUE) {
		DWORD mode;
		if (GetConsoleMode(hstdin, &mode)) {
			*active = (mode & ENABLE_ECHO_INPUT);
			return 0;
		}
	}
	return GetLastError();
}

static int setecho(int active)
{
	HANDLE hstdin = GetStdHandle(STD_INPUT_HANDLE);
	if (hstdin != INVALID_HANDLE_VALUE) {
		DWORD mode;
		if (GetConsoleMode(hstdin, &mode)) {
			mode = active ? (mode | ENABLE_ECHO_INPUT) : (mode & ~ENABLE_ECHO_INPUT);
			if (SetConsoleMode(hstdin, mode)) {
				return 0;
			}
		}
	}
	return GetLastError();
}

static int raiseerror(lua_State *L, int error)
{
	char buffer[256];
	DWORD res = FormatMessageA(FORMAT_MESSAGE_IGNORE_INSERTS|
	                           FORMAT_MESSAGE_FROM_SYSTEM,  /* formatting opts. */
	                           NULL,                        /* ignored */
	                           error,                       /* message id. */
	                           0,                           /* language id. */
	                           buffer,                      /* output buffer */
	                           sizeof(buffer)/sizeof(char), /* buffer size */
	                           NULL);                       /* ignored */
	if (res != 0) {
		DWORD msgerr = GetLastError();
		luaL_error(L, "failed to message for error %d (got error %d)", error, msgerr);
	}
	lua_pushlstring(L, buffer, res);
	lua_error(L);
}

#else

#include <unistd.h>
#include <termios.h>
#include <errno.h>
#include <string.h>

static int getecho(int *active)
{
	int fildes = fileno(stdin);
	struct termios opts;
	if (tcgetattr(fildes, &opts) == 0) {
		*active = opts.c_lflag & ECHO;
		return 0;
	}
	return errno;
}

static int setecho(int active)
{
	int fildes = fileno(stdin);
	struct termios opts;
	if (tcgetattr(fildes, &opts) == 0) {
		opts.c_lflag = active ? (opts.c_lflag | ECHO) : (opts.c_lflag & ~ECHO);
		if (tcsetattr(fildes, TCSANOW, &opts) == 0) {
			return 0;
		}
	}
	return errno;
}

static void raiseerror(lua_State *L, int code)
{
	lua_pushstring(L, strerror(code));
	lua_error(L);
}

#endif



static int l_getmode (lua_State *L)
{
	int active;
	int error = getecho(&active);
	if (error) raiseerror(L, error);
	lua_pushboolean(L, active);
	return 1;
}

static int l_setmode (lua_State *L)
{
	int error = setecho(lua_toboolean(L, 1));
	if (error) raiseerror(L, error);
	return 0;
}

static const luaL_Reg funcs[] = {
	{"getecho", l_getmode},
	{"setecho", l_setmode},
	{NULL, NULL}
};


LUAMOD_API int luaopen_openbus_util_echo (lua_State *L) {
	luaL_newlib(L, funcs);
	return 1;
}
