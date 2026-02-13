#include "llama_dart_wrapper.h"

#include <cstring>

#include <string>
#include <vector>

// Global log level (0=none, 1=debug, 2=info, 3=warn, 4=error)
static int g_dart_log_level = 3; // Default to WARN

static void llama_dart_native_log_callback(ggml_log_level level,
                                           const char *text, void *user_data) {
  (void)user_data;
  // Explicitly suppress all native logs for `none`.
  if (g_dart_log_level <= 0) {
    return;
  }

  // ggml levels: NONE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, CONT=5
  if ((int)level >= g_dart_log_level && level != GGML_LOG_LEVEL_NONE) {
    fputs(text, stderr);
    fflush(stderr);
  }
}

extern "C" {

LLAMA_API void llama_dart_set_log_level(int level) {
  if (level < 0) {
    level = 0;
  } else if (level > 4) {
    level = 4;
  }

  g_dart_log_level = level;
  // Set callbacks every time to ensure they are active
  llama_log_set(llama_dart_native_log_callback, nullptr);
  ggml_log_set(llama_dart_native_log_callback, nullptr);
}
}
