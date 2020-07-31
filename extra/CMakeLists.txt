if (CMAKE_CROSSCOMPILING)
    add_custom_target(txt2c
        COMMAND ${CMAKE_HOST_C_COMPILER} txt2c.c
            -o "${CMAKE_CURRENT_BINARY_DIR}/txt2c"
        DEPENDS txt2c.c)
else()
    add_executable(txt2c txt2c.c)
endif()
