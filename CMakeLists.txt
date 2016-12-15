cmake_minimum_required(VERSION 3.5)

project(luabox C CXX)

set(CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})
set(CMAKE_INCLUDE_PATH "${PROJECT_SOURCE_DIR}/cmake" ${CMAKE_INCLUDE_PATH})

#set(CMAKE_CXX_COMPILER      "clang++")
set(CMAKE_CXX_COMPILER      "g++")
set(CMAKE_CXX_FLAGS         "-fPIC -Wall --std=c++17")
#set(CMAKE_CXX_FLAGS         "-fPIC -Wall --std=c++14 -pg")
set(CMAKE_CXX_FLAGS_DEBUG   "-g")
set(CMAKE_CXX_FLAGS_RELEASE "-O4 -DNDEBUG")

# Define GNU standard installation directories
include(GNUInstallDirs)

add_subdirectory(src)
