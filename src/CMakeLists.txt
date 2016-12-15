find_package(LuaJIT REQUIRED)
include_directories(${LUAJIT_INCLUDE_DIR})
include(utils)

set(lua_modules)
lua_bytecode(lua_modules lua/cmdline.lua    luabox.cmdline)
lua_bytecode(lua_modules lua/command.lua    luabox.command)
lua_bytecode(lua_modules lua/config.lua     luabox.config)
lua_bytecode(lua_modules lua/exceptions.lua luabox.exceptions)
lua_bytecode(lua_modules lua/init.lua       luabox)
lua_bytecode(lua_modules lua/unit.lua       luabox.unit)
lua_bytecode(lua_modules lua/utils.lua      luabox.utils)

add_custom_target(generate_luabox_bytecode
      WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/lua
      DEPENDS ${lua_modules})

add_library(luabox SHARED
  ${lua_modules})

set_target_properties(luabox
  PROPERTIES
    LINKER_LANGUAGE C)

add_dependencies(luabox generate_luabox_bytecode)

target_link_libraries(luabox
  ${LUAJIT_LIBRARIES})

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/luabox.lua
  DESTINATION ${CMAKE_INSTALL_BINDIR}
  PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
              GROUP_READ GROUP_EXECUTE
              WORLD_READ WORLD_EXECUTE
  RENAME luabox)
install(TARGETS luabox DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/units
  DESTINATION ${CMAKE_INSTALL_LIBEXECDIR}/${PROJECT_NAME})
