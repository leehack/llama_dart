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

set(LLAMA_BUILD_COMMON OFF CACHE BOOL "Build llama.cpp common library" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Build llama.cpp tests" FORCE)
# Manually define mtmd to avoid building tools in the submodule and to skip modifying its CMakeLists.txt
add_library(mtmd STATIC
    llama_cpp/tools/mtmd/mtmd.cpp
    llama_cpp/tools/mtmd/mtmd-audio.cpp
    llama_cpp/tools/mtmd/mtmd-helper.cpp
    llama_cpp/tools/mtmd/clip.cpp
    llama_cpp/tools/mtmd/mtmd.h
    llama_cpp/tools/mtmd/mtmd-helper.h
    llama_cpp/tools/mtmd/clip.h
    llama_cpp/tools/mtmd/clip-impl.h
    llama_cpp/tools/mtmd/clip-model.h
    llama_cpp/tools/mtmd/clip-graph.h
    llama_cpp/tools/mtmd/models/models.h
    llama_cpp/tools/mtmd/models/cogvlm.cpp
    llama_cpp/tools/mtmd/models/conformer.cpp
    llama_cpp/tools/mtmd/models/glm4v.cpp
    llama_cpp/tools/mtmd/models/internvl.cpp
    llama_cpp/tools/mtmd/models/kimivl.cpp
    llama_cpp/tools/mtmd/models/llama4.cpp
    llama_cpp/tools/mtmd/models/llava.cpp
    llama_cpp/tools/mtmd/models/minicpmv.cpp
    llama_cpp/tools/mtmd/models/pixtral.cpp
    llama_cpp/tools/mtmd/models/qwen2vl.cpp
    llama_cpp/tools/mtmd/models/qwen3vl.cpp
    llama_cpp/tools/mtmd/models/siglip.cpp
    llama_cpp/tools/mtmd/models/whisper-enc.cpp
    llama_cpp/tools/mtmd/models/mobilenetv5.cpp
    llama_cpp/tools/mtmd/models/youtuvl.cpp
)

target_include_directories(mtmd PUBLIC llama_cpp/tools/mtmd)
target_include_directories(mtmd PRIVATE llama_cpp llama_cpp/vendor llama_cpp/tools/mtmd/models)
target_link_libraries(mtmd PUBLIC ggml llama Threads::Threads)
target_compile_features(mtmd PRIVATE cxx_std_17)

set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Build llama.cpp examples" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Build llama.cpp server" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "Build llama.cpp tools" FORCE)

add_subdirectory(llama_cpp)

set(CONSOLIDATED_LIBS llama ggml ggml-base ggml-cpu ggml-vulkan ggml-blas ggml-metal ggml-cuda mtmd)

# mtmd needs these to export symbols properly when built as a static lib merged into shared
target_compile_definitions(mtmd PRIVATE 
    GGML_SHARED LLAMA_SHARED 
    GGML_BUILD LLAMA_BUILD 
    GGML_BACKEND_SHARED GGML_BACKEND_BUILD)

if (APPLE)
    # Support both STATIC and SHARED for Apple platforms
    if (LLAMADART_SHARED)
        add_library(llamadart_lib SHARED "llamadart_empty.cpp")
        # Use -Wl,-force_load to ensure all symbols from the static 'llama' lib are included in the dylib
        target_link_libraries(llamadart_lib PUBLIC -Wl,-force_load llama -Wl,-force_load mtmd)
    else()
        add_library(llamadart_lib STATIC "llamadart_empty.cpp")
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

    add_library(llamadart_lib SHARED "llamadart_windows.cpp" ${COMBINED_OBJECTS})
    target_link_libraries(llamadart_lib PUBLIC ${ACTIVE_LIBS})
    target_compile_definitions(llamadart_lib PRIVATE LLAMA_SHARED GGML_SHARED LLAMA_BUILD GGML_BUILD)
elseif (CMAKE_SYSTEM_NAME MATCHES "Android|Linux" OR MINGW)
    add_library(llamadart_lib SHARED "llamadart_empty.cpp")
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
    add_library(llamadart_lib SHARED "llamadart_empty.cpp")
    target_link_libraries(llamadart_lib PUBLIC llama)
endif()

# Set the output name to 'llamadart' consistently
set_target_properties(llamadart_lib PROPERTIES 
    OUTPUT_NAME llamadart
    LIBRARY_OUTPUT_NAME llamadart
)
