add_test(
    NAME tuple_keydef.test.lua
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tuple_keydef.test.lua
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR})

add_test(
    NAME hot_reload.test.lua
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/hot_reload.test.lua
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
