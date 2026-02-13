cmake_minimum_required(VERSION 3.20)
project(llamadart_webgpu_bridge C CXX)

if (NOT EMSCRIPTEN)
    message(FATAL_ERROR "This project must be configured with emcmake/emcc")
endif()

if (NOT DEFINED LLAMA_CPP_DIR)
    set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/llama_cpp")
endif()

if (NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "LLAMA_CPP_DIR is invalid: ${LLAMA_CPP_DIR}")
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/artifacts")

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_HTTPLIB OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_HTML OFF CACHE BOOL "" FORCE)
set(LLAMA_WASM_SINGLE_FILE OFF CACHE BOOL "" FORCE)

set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_WEBGPU ON CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_CPP_DIR}" "${CMAKE_BINARY_DIR}/llama_cpp")

find_package(Threads REQUIRED)

set(MTMD_AUDIO_SRC "${LLAMA_CPP_DIR}/tools/mtmd/mtmd-audio.cpp")
set(MTMD_AUDIO_PATCHED "${CMAKE_BINARY_DIR}/generated/mtmd-audio-single-thread.cpp")

file(READ "${MTMD_AUDIO_SRC}" MTMD_AUDIO_CONTENT)
string(FIND "${MTMD_AUDIO_CONTENT}" "4,  // n_threads" MTMD_AUDIO_THREAD_MARKER_INDEX)
if (MTMD_AUDIO_THREAD_MARKER_INDEX EQUAL -1)
    message(FATAL_ERROR "mtmd-audio.cpp thread marker not found; update single-thread wasm patch")
endif()
string(REPLACE
    "4,  // n_threads"
    "1,  // n_threads (patched for single-threaded wasm)"
    MTMD_AUDIO_CONTENT
    "${MTMD_AUDIO_CONTENT}")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/generated")
file(WRITE "${MTMD_AUDIO_PATCHED}" "${MTMD_AUDIO_CONTENT}")

add_library(llamadart_mtmd STATIC
    "${LLAMA_CPP_DIR}/tools/mtmd/mtmd.cpp"
    "${MTMD_AUDIO_PATCHED}"
    "${LLAMA_CPP_DIR}/tools/mtmd/mtmd-helper.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/clip.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/cogvlm.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/conformer.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/glm4v.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/internvl.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/kimivl.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/kimik25.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/llama4.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/llava.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/minicpmv.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/pixtral.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/qwen2vl.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/qwen3vl.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/siglip.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/whisper-enc.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/mobilenetv5.cpp"
    "${LLAMA_CPP_DIR}/tools/mtmd/models/youtuvl.cpp"
)

target_compile_features(llamadart_mtmd PRIVATE cxx_std_17)
target_compile_options(llamadart_mtmd PRIVATE
    "-sMEMORY64=1"
)
target_include_directories(llamadart_mtmd PRIVATE
    "${LLAMA_CPP_DIR}/tools/mtmd"
    "${LLAMA_CPP_DIR}"
    "${LLAMA_CPP_DIR}/vendor"
)
target_link_libraries(llamadart_mtmd PRIVATE ggml llama Threads::Threads)

if (NOT MSVC)
    target_compile_options(llamadart_mtmd PRIVATE -Wno-cast-qual)
endif()

add_executable(llama_webgpu_core src/llama_webgpu_core.cpp)

target_compile_features(llama_webgpu_core PRIVATE cxx_std_17)

target_compile_options(llama_webgpu_core PRIVATE
    "-sMEMORY64=1"
)

target_include_directories(llama_webgpu_core PRIVATE
    "${LLAMA_CPP_DIR}/include"
    "${LLAMA_CPP_DIR}/ggml/include"
    "${LLAMA_CPP_DIR}/tools/mtmd"
)

target_link_libraries(llama_webgpu_core PRIVATE llama llamadart_mtmd)

target_link_options(llama_webgpu_core PRIVATE
    "-sMEMORY64=1"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sASSERTIONS=1"
    "-sJSPI=1"
    "-sJSPI_EXPORTS=['llamadart_webgpu_probe','llamadart_webgpu_load_model','llamadart_webgpu_mmproj_load','llamadart_webgpu_tokenize_to_json','llamadart_webgpu_detokenize_from_json','llamadart_webgpu_generate','llamadart_webgpu_begin_generation','llamadart_webgpu_next_token','llamadart_webgpu_shutdown']"
    "-sMODULARIZE=1"
    "-sEXPORT_ES6=1"
    "-sEXPORT_NAME=createLlamaWebGpuCoreModule"
    "-sENVIRONMENT=web,worker"
    "-sEXPORTED_RUNTIME_METHODS=['FS','ccall','UTF8ToString']"
    "-sEXPORTED_FUNCTIONS=['_main','_llamadart_webgpu_probe','_llamadart_webgpu_backends_json','_llamadart_webgpu_last_error','_llamadart_webgpu_load_model','_llamadart_webgpu_mmproj_load','_llamadart_webgpu_mmproj_free','_llamadart_webgpu_mmproj_supports_vision','_llamadart_webgpu_mmproj_supports_audio','_llamadart_webgpu_media_clear_pending','_llamadart_webgpu_media_add_file','_llamadart_webgpu_media_add_encoded','_llamadart_webgpu_media_add_rgb','_llamadart_webgpu_media_add_audio_f32','_llamadart_webgpu_tokenize_to_json','_llamadart_webgpu_last_tokens_json','_llamadart_webgpu_detokenize_from_json','_llamadart_webgpu_last_detokenized','_llamadart_webgpu_generate','_llamadart_webgpu_begin_generation','_llamadart_webgpu_next_token','_llamadart_webgpu_last_piece','_llamadart_webgpu_end_generation','_llamadart_webgpu_request_cancel','_llamadart_webgpu_last_output','_llamadart_webgpu_get_context_size','_llamadart_webgpu_model_meta_json','_llamadart_webgpu_shutdown']"
)

set_target_properties(llama_webgpu_core PROPERTIES
    OUTPUT_NAME "llama_webgpu_core"
    SUFFIX ".js"
)
