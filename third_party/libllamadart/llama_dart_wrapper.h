#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "llama.h"

// Opaque pointer to the templates structure

// Sets the log level for llama.cpp
void llama_dart_set_log_level(int level);

#ifdef __cplusplus
}
#endif
