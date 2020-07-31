# Compile *.lua files into *.lua.c sources
set(lua_sources)
lua_source(lua_sources key_def.lua)

set_property(DIRECTORY PROPERTY ADDITIONAL_MAKE_CLEAN_FILES ${lua_sources})

set(module_sources
    init.c
    key_def.c
    ${lua_sources}
)

add_library(${PROJECT_NAME} SHARED ${module_sources})

# Drop 'lib' prefix from the filename: libfoo.so -> foo.so.
set_target_properties(${PROJECT_NAME} PROPERTIES PREFIX "")

# The dynamic library will be loaded from tarantool executable
# and will use symbols from it. So it is completely okay to have
# unresolved symbols at build time.
if (APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
endif()

install(TARGETS ${PROJECT_NAME} LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/)
