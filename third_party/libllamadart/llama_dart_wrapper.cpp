#include "llama_dart_wrapper.h"

#include <cstring>

#include <string>
#include <vector>

// Global log level
static int g_dart_log_level = 3; // Default to WARN (3)

static void llama_dart_native_log_callback(ggml_log_level level,
                                           const char *text, void *user_data) {
  (void)user_data;
  // Map ggml_log_level to our simple integer level
  // DEBUG=1, INFO=2, WARN=3, ERROR=4, CONT=5
  if ((int)level >= g_dart_log_level && (int)level != 0) {
    fputs(text, stderr);
    fflush(stderr);
  }
}

extern "C" {

LLAMA_API void llama_dart_set_log_level(int level) {
  g_dart_log_level = level;
  // Set callbacks every time to ensure they are active
  llama_log_set(llama_dart_native_log_callback, nullptr);
  ggml_log_set(llama_dart_native_log_callback, nullptr);
}
}
