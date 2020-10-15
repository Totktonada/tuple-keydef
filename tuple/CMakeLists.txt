# Compile *.lua files into *.lua.c sources
set(lua_sources)
lua_source(lua_sources keydef.lua)

set_property(DIRECTORY PROPERTY ADDITIONAL_MAKE_CLEAN_FILES ${lua_sources})

set(module_sources
    util.c
    keydef.c
    ${lua_sources}
)

set(LIBSUBDIR tuple)
set(LIBNAME keydef)
add_library(${LIBNAME} SHARED ${module_sources})

# Without this magic .so is not rebuilt on .lua changes.
#
# XXX: Verify it again.
add_custom_target(build_lua_sources DEPENDS ${lua_sources})
add_dependencies(${LIBNAME} build_lua_sources)

# Drop 'lib' prefix from the filename: libfoo.so -> foo.so.
set_target_properties(${LIBNAME} PROPERTIES PREFIX "")

# The dynamic library will be loaded from tarantool executable
# and will use symbols from it. So it is completely okay to have
# unresolved symbols at build time.
if (APPLE)
    set_target_properties(${LIBNAME} PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
endif()

install(TARGETS ${LIBNAME} LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/${LIBSUBDIR})
