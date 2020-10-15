cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(tuple_keydef C)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()


set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

include(cmake/compiler.cmake)
include(cmake/utils.cmake)

# Find Tarantool.
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

add_subdirectory(extra)
add_subdirectory(tuple)

enable_testing()
add_subdirectory(test)
