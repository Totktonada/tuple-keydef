add_test(
    NAME tuple_keydef.test.lua
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/runtest.sh tuple_keydef.test.lua)

# Add LUA_CPATH that points to the location, where the built
# module (tuple/keydef.{so,dylib}) is placed. It is different
# from the source directory, when out-of-source build is used
# (`cmake /path/to/sources`, not just `cmake .`).
#
# Double semicolons (';;') are replaced with default paths.
set(TEST_ENV
    "LUA_CPATH=${CMAKE_CURRENT_BINARY_DIR}/../?${CMAKE_SHARED_LIBRARY_SUFFIX}\\\;\\\;")
set_tests_properties(tuple_keydef.test.lua PROPERTIES ENVIRONMENT ${TEST_ENV})
