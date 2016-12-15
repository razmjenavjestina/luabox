# A helper function to compile *.lua source into object containing bytecode
function(lua_bytecode varname filename)
  if (IS_ABSOLUTE "${filename}")
    set (srcfile "${filename}")
    set (dstfile "${filename}.o")
  else(IS_ABSOLUTE "${filename}")
    set (srcfile "${CMAKE_CURRENT_SOURCE_DIR}/${filename}")
    set (dstfile "${CMAKE_CURRENT_BINARY_DIR}/${filename}.o")
  endif(IS_ABSOLUTE "${filename}")
  get_filename_component(modname ${filename} NAME_WE)
  foreach(f ${ARGN})
    set(modname ${f})
  endforeach()
  get_filename_component(_name ${dstfile} NAME)
  string(REGEX REPLACE "${_name}$" "" dstdir ${dstfile})
  if (IS_DIRECTORY ${dstdir})
  else()
    file(MAKE_DIRECTORY ${dstdir})
  endif()

  ADD_CUSTOM_COMMAND(OUTPUT ${dstfile}
    COMMENT "Compiling lua module \"${modname}\" to bytecode ..."
    COMMAND luajit -bgn ${modname} ${srcfile} ${dstfile}
    DEPENDS ${srcfile})

  set(var ${${varname}})
  set(${varname} ${var} ${dstfile} PARENT_SCOPE)
endfunction()
