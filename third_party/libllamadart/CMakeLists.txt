cmake_minimum_required(VERSION 3.14)
project(llamadart C CXX)

# Include llama.cpp options/build
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

add_subdirectory(../llama_cpp llama_cpp)

# Define our library
add_library(llamadart SHARED
    llama_dart_wrapper.cpp

)

# Link against llama and common
target_link_libraries(llamadart PRIVATE llama common)

# Include directories
target_include_directories(llamadart PRIVATE
    ../llama_cpp/include
    ../llama_cpp/common
    ../llama_cpp/src
)

# Properties
set_target_properties(llamadart PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET default
)
