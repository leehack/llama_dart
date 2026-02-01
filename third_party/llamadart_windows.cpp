// This file is used to trigger symbol exports on Windows when building the consolidated DLL.
#ifdef _WIN32
#define LLAMA_API_EXPORT
#define GGML_API_EXPORT
#define GGML_BACKEND_API_EXPORT
#endif

#include "llama_cpp/include/llama.h"
#include "llama_cpp/ggml/include/ggml.h"
#include "llama_cpp/ggml/include/ggml-backend.h"

extern "C" {
    // Dummy symbol to ensure the object file is linked and can provide the exports trigger
    __declspec(dllexport) void llamadart_windows_init() {}
}
