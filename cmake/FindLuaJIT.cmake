# Finds LuaJIT library
#
#  To explicitly request use of LuaJIT at a given
#  prefix, use -DLUAJIT_PREFIX=/path/to/LuaJIT.
#
#  LUAJIT_INCLUDE_DIR - where to find lua.h, etc.
#  LUAJIT_LIBRARIES   - List of libraries when using luajit.
#  LUAJIT_FOUND       - True if luajit found.
#

#
# Check if there is a system LuaJIT availaible
#
macro (luajit_try_system)
    find_path (LUAJIT_INCLUDE "lua.h" PATH_SUFFIXES luajit-2.1 luajit)
    find_library (LUAJIT_LIB NAMES luajit luajit-5.1 PATH_SUFFIXES x86_64-linux-gnu)
    if (LUAJIT_INCLUDE AND LUAJIT_LIB)
        message (STATUS "include: ${LUAJIT_INCLUDE}, lib: ${LUAJIT_LIB}")
        message (STATUS "Found a system-wide LuaJIT.")
    else()
        message (FATAL_ERROR "Not found a system LuaJIT")
    endif()
endmacro()


#
# Check if there is a usable LuaJIT at the given prefix path.
#
macro (luajit_try_prefix)
    find_path (LUAJIT_INCLUDE "lua.h" ${LUAJIT_PREFIX} NO_DEFAULT_PATH)
    find_library (LUAJIT_LIB "luajit" ${LUAJIT_PREFIX} NO_DEFAULT_PATH)
    if (LUAJIT_INCLUDE AND LUAJIT_LIB)
        message (STATUS "include: ${LUAJIT_INCLUDE}, lib: ${LUAJIT_LIB}")
        message (STATUS "Found a LuaJIT in '${LUAJIT_PREFIX}'")
    else()
        message (FATAL_ERROR "Couldn't find LuaJIT in '${LUAJIT_PREFIX}'")
    endif()
endmacro()

if (LUAJIT_PREFIX)
    # trying to build with specified LuaJIT.
    luajit_try_prefix()
else()
    luajit_try_system()
endif()


set(LuaJIT_FIND_REQUIRED TRUE)
# Handle the QUIETLY and REQUIRED arguments and set XXX_FOUND to TRUE if all listed variables are TRUE
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LuaJIT
    REQUIRED_VARS LUAJIT_INCLUDE LUAJIT_LIB)

set(LUAJIT_INCLUDE_DIR ${LUAJIT_INCLUDE})
set(LUAJIT_LIBRARIES ${LUAJIT_LIB})
