find_program(ECHO echo)

# A helper function to compile *.lua source into *.lua.c sources
function(lua_source varname filename)
    if (IS_ABSOLUTE "${filename}")
        set (srcfile "${filename}")
        set (tmpfile "${filename}.new.c")
        set (dstfile "${filename}.c")
    else(IS_ABSOLUTE "${filename}")
        set (srcfile "${CMAKE_CURRENT_SOURCE_DIR}/${filename}")
        set (tmpfile "${CMAKE_CURRENT_BINARY_DIR}/${filename}.new.c")
        set (dstfile "${CMAKE_CURRENT_BINARY_DIR}/${filename}.c")
    endif(IS_ABSOLUTE "${filename}")
    get_filename_component(module ${filename} NAME_WE)
    get_filename_component(_name ${dstfile} NAME)
    string(REGEX REPLACE "${_name}$" "" dstdir ${dstfile})
    if (IS_DIRECTORY ${dstdir})
    else()
        file(MAKE_DIRECTORY ${dstdir})
    endif()

    # NB: We prepend the array name with the project name to avoid
    # possible name collisions (say, with the same named built-in
    # tarantool module).
    ADD_CUSTOM_COMMAND(OUTPUT ${dstfile}
        COMMAND ${ECHO} 'const char ${PROJECT_NAME}_${module}_lua[] =' > ${tmpfile}
        COMMAND ${CMAKE_BINARY_DIR}/extra/txt2c ${srcfile} >> ${tmpfile}
        COMMAND ${ECHO} '\;' >> ${tmpfile}
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${tmpfile} ${dstfile}
        COMMAND ${CMAKE_COMMAND} -E remove ${tmpfile}
        DEPENDS ${srcfile} txt2c)

    set(var ${${varname}})
    set(${varname} ${var} ${dstfile} PARENT_SCOPE)
endfunction()
