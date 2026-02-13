cmake_minimum_required(VERSION 3.14)
project(llamadart_native)

find_package(Threads REQUIRED)

# Force PIC so we can link static libs into shared
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Force llama.cpp to build static libraries so we can bundle them
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libraries" FORCE)

# Add llama.cpp as a subdirectory
set(LLAMA_BUILD_NUMBER 0 CACHE STRING "Llama build number" FORCE)
set(LLAMA_INSTALL_VERSION 0.0.0 CACHE STRING "Llama install version" FORCE)

# Common Llama.cpp options
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "Build llama.cpp common library" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Build llama.cpp tests" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Build llama.cpp examples" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Build llama.cpp server" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "Build llama.cpp tools" FORCE)
set(LLAMA_HTTPLIB OFF CACHE BOOL "Disable httplib" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "Disable OpenSSL" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "Disable native CPU optimizations for portability" FORCE)

# Set defaults for Release builds
if (CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
endif()

add_subdirectory(llama_cpp/tools/mtmd EXCLUDE_FROM_ALL)
add_subdirectory(llama_cpp)

set(CONSOLIDATED_LIBS llama ggml ggml-base ggml-cpu ggml-vulkan ggml-blas ggml-metal ggml-cuda mtmd)

# mtmd needs these to export symbols properly when built as a static lib merged into shared
target_compile_definitions(mtmd PRIVATE 
    GGML_SHARED LLAMA_SHARED 
    GGML_BUILD LLAMA_BUILD 
    GGML_BACKEND_SHARED GGML_BACKEND_BUILD)

if (APPLE)
    # Default Metal options for macOS/iOS
    set(GGML_METAL ON CACHE BOOL "Enable Metal" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "Embed Metal library" FORCE)
    set(GGML_METAL_USE_BF16 OFF CACHE BOOL "Use BF16 in Metal" FORCE)

    # Support both STATIC and SHARED for Apple platforms
    if (LLAMADART_SHARED)
        add_library(llamadart_lib SHARED "libllamadart/llama_dart_wrapper.cpp")
        # Use -Wl,-force_load to ensure all symbols from the static 'llama' lib are included in the dylib
        target_link_libraries(llamadart_lib PUBLIC -Wl,-force_load llama -Wl,-force_load mtmd)
    else()
        add_library(llamadart_lib STATIC "libllamadart/llama_dart_wrapper.cpp")
        # Use -Wl,-all_load for static library consolidation
        target_link_libraries(llamadart_lib PUBLIC -Wl,-all_load llama -Wl,-all_load mtmd)
    endif()
elseif (MSVC)
    # On MSVC, we want to consolidate everything into a single DLL.
    set(COMBINED_OBJECTS "")
    set(ACTIVE_LIBS "")
    foreach(LIB ${CONSOLIDATED_LIBS})
        if(TARGET ${LIB})
            list(APPEND ACTIVE_LIBS ${LIB})
            target_compile_definitions(${LIB} PRIVATE 
                GGML_SHARED LLAMA_SHARED 
                GGML_BUILD LLAMA_BUILD 
                GGML_BACKEND_SHARED GGML_BACKEND_BUILD)
            list(APPEND COMBINED_OBJECTS $<TARGET_OBJECTS:${LIB}>)
        endif()
    endforeach()

    add_library(llamadart_lib SHARED "libllamadart/llama_dart_wrapper.cpp" ${COMBINED_OBJECTS})
    target_link_libraries(llamadart_lib PUBLIC ${ACTIVE_LIBS})
    target_compile_definitions(llamadart_lib PRIVATE LLAMA_SHARED GGML_SHARED LLAMA_BUILD GGML_BUILD)
elseif (CMAKE_SYSTEM_NAME MATCHES "Android|Linux" OR MINGW)
    add_library(llamadart_lib SHARED "libllamadart/llama_dart_wrapper.cpp")
    if (MINGW)
        target_link_options(llamadart_lib PRIVATE -Wl,--export-all-symbols)
    endif()

    set(WHOLE_ARCHIVE_LIBS "")
    foreach(LIB ${CONSOLIDATED_LIBS})
        if(TARGET ${LIB})
            list(APPEND WHOLE_ARCHIVE_LIBS ${LIB})
        endif()
    endforeach()

    target_link_libraries(llamadart_lib PUBLIC -Wl,--whole-archive ${WHOLE_ARCHIVE_LIBS} -Wl,--no-whole-archive)
else()
    add_library(llamadart_lib SHARED "libllamadart/llama_dart_wrapper.cpp")
    target_link_libraries(llamadart_lib PUBLIC llama)
endif()

# Set the output name to 'llamadart' consistently
set_target_properties(llamadart_lib PROPERTIES 
    OUTPUT_NAME llamadart
    LIBRARY_OUTPUT_NAME llamadart
)

target_include_directories(llamadart_lib PRIVATE
    llama_cpp/include
    llama_cpp/src
    libllamadart
)
