#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <regex>
#include <string>
#include <vector>

#include <emscripten/emscripten.h>

#include "ggml-backend.h"
#include "llama.h"
#include "mtmd-helper.h"
#include "mtmd.h"

namespace {

struct runtime_state {
  llama_model * model = nullptr;
  llama_context * ctx = nullptr;
  const llama_vocab * vocab = nullptr;
  mtmd_context * mm_ctx = nullptr;
  uint32_t n_ctx = 0;
};

runtime_state g_state;

bool g_backend_initialized = false;
bool g_has_webgpu = false;
bool g_generation_active = false;
bool g_cancel_requested = false;
llama_sampler * g_active_sampler = nullptr;

std::string g_last_error;
std::string g_last_output;
std::string g_last_piece;
std::string g_last_tokens_json = "[]";
std::string g_last_detokenized;
std::string g_backend_json = "[]";
std::string g_model_meta_json = "{}";

std::vector<mtmd_bitmap *> g_pending_media;

std::string to_lower(std::string value) {
  std::transform(
      value.begin(),
      value.end(),
      value.begin(),
      [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

std::string escape_json(const std::string & value) {
  std::string escaped;
  escaped.reserve(value.size() + 8);
  for (const char c : value) {
    switch (c) {
      case '\\':
        escaped += "\\\\";
        break;
      case '"':
        escaped += "\\\"";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        escaped += c;
        break;
    }
  }
  return escaped;
}

void set_error(const std::string & message) {
  g_last_error = message;
}

void clear_error() {
  g_last_error.clear();
}

void clear_pending_media() {
  for (mtmd_bitmap * bitmap : g_pending_media) {
    if (bitmap != nullptr) {
      mtmd_bitmap_free(bitmap);
    }
  }
  g_pending_media.clear();
}

void ensure_backend_initialized() {
  if (!g_backend_initialized) {
    llama_backend_init();
    g_backend_initialized = true;
  }
}

void end_generation_state() {
  if (g_active_sampler != nullptr) {
    llama_sampler_free(g_active_sampler);
    g_active_sampler = nullptr;
  }
  g_generation_active = false;
  g_last_piece.clear();
  g_cancel_requested = false;
}

void free_runtime() {
  end_generation_state();

  clear_pending_media();

  if (g_state.mm_ctx != nullptr) {
    mtmd_free(g_state.mm_ctx);
    g_state.mm_ctx = nullptr;
  }

  if (g_state.ctx != nullptr) {
    llama_free(g_state.ctx);
    g_state.ctx = nullptr;
  }

  if (g_state.model != nullptr) {
    llama_model_free(g_state.model);
    g_state.model = nullptr;
  }

  g_state.vocab = nullptr;
  g_state.n_ctx = 0;
  g_last_output.clear();
  g_last_piece.clear();
  g_last_tokens_json = "[]";
  g_last_detokenized.clear();
  g_model_meta_json = "{}";
}

std::vector<std::string> collect_backend_labels() {
  std::vector<std::string> labels;

  const size_t count = ggml_backend_dev_count();
  labels.reserve(count);

  for (size_t i = 0; i < count; ++i) {
    ggml_backend_dev_t dev = ggml_backend_dev_get(i);
    if (dev == nullptr) {
      continue;
    }

    const char * dev_name = ggml_backend_dev_name(dev);
    if (dev_name == nullptr) {
      continue;
    }

    std::string label = dev_name;

    ggml_backend_reg_t reg = ggml_backend_dev_backend_reg(dev);
    if (reg != nullptr) {
      const char * reg_name = ggml_backend_reg_name(reg);
      if (reg_name != nullptr && std::strlen(reg_name) > 0) {
        const std::string reg_str = reg_name;
        const std::string dev_str = dev_name;
        if (to_lower(reg_str) == to_lower(dev_str)) {
          label = reg_str;
        } else {
          label = reg_str + " (" + dev_str + ")";
        }
      }
    }

    labels.push_back(label);
  }

  return labels;
}

void refresh_backend_probe() {
  clear_error();
  ensure_backend_initialized();

  ggml_backend_load_all();

  const std::vector<std::string> labels = collect_backend_labels();

  std::string json = "[";
  for (size_t i = 0; i < labels.size(); ++i) {
    if (i > 0) {
      json += ",";
    }
    json += '"';
    json += escape_json(labels[i]);
    json += '"';
  }
  json += "]";
  g_backend_json = json;

  g_has_webgpu = false;
  for (const std::string & label : labels) {
    const std::string lowered = to_lower(label);
    if (lowered.find("webgpu") != std::string::npos ||
        lowered.find("wgpu") != std::string::npos) {
      g_has_webgpu = true;
      break;
    }
  }
}

std::string read_model_meta_string(
    const llama_model * model,
    const int32_t index,
    const bool read_key) {
  size_t buf_size = read_key ? 1024 : 65536;

  for (int attempt = 0; attempt < 6; ++attempt) {
    std::vector<char> buf(buf_size, '\0');
    const int32_t rc = read_key
        ? llama_model_meta_key_by_index(model, index, buf.data(), buf.size())
        : llama_model_meta_val_str_by_index(model, index, buf.data(), buf.size());

    if (rc < 0) {
      buf_size *= 2;
      continue;
    }

    if (static_cast<size_t>(rc) >= buf_size) {
      buf_size = static_cast<size_t>(rc) + 1;
      continue;
    }

    return std::string(buf.data());
  }

  return "";
}

void rebuild_model_metadata_json() {
  if (g_state.model == nullptr) {
    g_model_meta_json = "{}";
    return;
  }

  const int32_t count = llama_model_meta_count(g_state.model);
  if (count <= 0) {
    g_model_meta_json = "{}";
    return;
  }

  std::string json = "{";
  bool wrote_any = false;

  for (int32_t i = 0; i < count; ++i) {
    const std::string key = read_model_meta_string(g_state.model, i, true);
    const std::string value = read_model_meta_string(g_state.model, i, false);

    if (key.empty()) {
      continue;
    }

    if (wrote_any) {
      json += ",";
    }
    wrote_any = true;

    json += '"';
    json += escape_json(key);
    json += "\":";
    json += '"';
    json += escape_json(value);
    json += '"';
  }

  json += "}";
  g_model_meta_json = json;
}

bool ensure_loaded() {
  if (g_state.model == nullptr || g_state.ctx == nullptr || g_state.vocab == nullptr) {
    set_error("Model is not loaded");
    return false;
  }
  return true;
}

bool tokenize_text(
    const std::string & text,
    const bool add_special,
    std::vector<llama_token> & out) {
  if (!ensure_loaded()) {
    return false;
  }

  int32_t capacity = static_cast<int32_t>(text.size()) + 8;
  if (capacity < 32) {
    capacity = 32;
  }

  out.assign(static_cast<size_t>(capacity), 0);
  int32_t n_tokens = llama_tokenize(
      g_state.vocab,
      text.c_str(),
      static_cast<int32_t>(text.size()),
      out.data(),
      static_cast<int32_t>(out.size()),
      add_special,
      true);

  if (n_tokens < 0) {
    const int32_t required = -n_tokens;
    out.assign(static_cast<size_t>(required), 0);
    n_tokens = llama_tokenize(
        g_state.vocab,
        text.c_str(),
        static_cast<int32_t>(text.size()),
        out.data(),
        static_cast<int32_t>(out.size()),
        add_special,
        true);
  }

  if (n_tokens < 0) {
    set_error("Prompt tokenization failed");
    return false;
  }

  out.resize(static_cast<size_t>(n_tokens));
  return true;
}

bool decode_tokens(const std::vector<llama_token> & tokens) {
  if (!ensure_loaded()) {
    return false;
  }

  if (tokens.empty()) {
    set_error("Cannot decode empty token sequence");
    return false;
  }

  int32_t max_batch = static_cast<int32_t>(llama_n_batch(g_state.ctx));
  if (max_batch <= 0) {
    max_batch = 512;
  }

  for (size_t offset = 0; offset < tokens.size(); offset += static_cast<size_t>(max_batch)) {
    const int32_t count = static_cast<int32_t>(
        std::min(tokens.size() - offset, static_cast<size_t>(max_batch)));

    llama_token * ptr = const_cast<llama_token *>(tokens.data() + offset);
    const int rc = llama_decode(g_state.ctx, llama_batch_get_one(ptr, count));
    if (rc != 0) {
      set_error("llama_decode failed while processing prompt");
      return false;
    }
  }

  return true;
}

std::string token_to_piece(const llama_token token, const bool special) {
  if (!ensure_loaded()) {
    return "";
  }

  std::vector<char> buf(256, '\0');
  int32_t n =
      llama_token_to_piece(g_state.vocab, token, buf.data(), buf.size(), 0, special);

  if (n < 0) {
    buf.assign(static_cast<size_t>(-n) + 8, '\0');
    n = llama_token_to_piece(g_state.vocab, token, buf.data(), buf.size(), 0, special);
  }

  if (n < 0) {
    return "";
  }

  return std::string(buf.data(), static_cast<size_t>(n));
}

bool should_abort_callback(void * /*data*/) {
  return g_cancel_requested;
}

std::string serialize_tokens_json(const std::vector<llama_token> & tokens) {
  std::string json = "[";
  for (size_t i = 0; i < tokens.size(); ++i) {
    if (i > 0) {
      json += ",";
    }
    json += std::to_string(tokens[i]);
  }
  json += "]";
  return json;
}

void parse_token_list(const char * token_text, std::vector<llama_token> & out_tokens) {
  out_tokens.clear();
  if (token_text == nullptr) {
    return;
  }

  const char * p = token_text;
  while (*p != '\0') {
    while (*p != '\0' &&
           !std::isdigit(static_cast<unsigned char>(*p)) &&
           *p != '-' &&
           *p != '+') {
      ++p;
    }

    if (*p == '\0') {
      break;
    }

    char * end = nullptr;
    const long value = std::strtol(p, &end, 10);
    if (end == p) {
      ++p;
      continue;
    }

    out_tokens.push_back(static_cast<llama_token>(value));
    p = end;
  }
}

void replace_all_inplace(
    std::string & text,
    const std::string & from,
    const std::string & to) {
  if (from.empty()) {
    return;
  }

  size_t start = 0;
  while (true) {
    const size_t pos = text.find(from, start);
    if (pos == std::string::npos) {
      break;
    }

    text.replace(pos, from.size(), to);
    start = pos + to.size();
  }
}

size_t count_occurrences(const std::string & text, const std::string & pattern) {
  if (pattern.empty()) {
    return 0;
  }

  size_t count = 0;
  size_t start = 0;
  while (true) {
    const size_t pos = text.find(pattern, start);
    if (pos == std::string::npos) {
      break;
    }
    ++count;
    start = pos + pattern.size();
  }
  return count;
}

std::string normalize_media_markers(const std::string & prompt, const size_t media_count) {
  const char * marker_ptr = mtmd_default_marker();
  const std::string marker = marker_ptr == nullptr
      ? std::string("<__media__>")
      : std::string(marker_ptr);

  std::string normalized = prompt;

  replace_all_inplace(normalized, "<image>", marker);
  replace_all_inplace(normalized, "[IMG]", marker);
  replace_all_inplace(normalized, "<|image|>", marker);
  replace_all_inplace(normalized, "<img>", marker);
  replace_all_inplace(normalized, "<|img|>", marker);
  replace_all_inplace(normalized, "<audio>", marker);
  replace_all_inplace(normalized, "<|audio|>", marker);

  normalized = std::regex_replace(normalized, std::regex("<\\|image_\\d+\\|>"), marker);
  normalized = std::regex_replace(normalized, std::regex("<\\|audio_\\d+\\|>"), marker);

  if (media_count == 0) {
    return normalized;
  }

  const size_t marker_count = count_occurrences(normalized, marker);
  if (marker_count >= media_count) {
    return normalized;
  }

  const size_t missing = media_count - marker_count;
  std::string marker_block;
  for (size_t i = 0; i < missing; ++i) {
    if (!marker_block.empty()) {
      marker_block += ' ';
    }
    marker_block += marker;
  }

  const size_t user_cap_pos = normalized.find("User:");
  if (user_cap_pos != std::string::npos) {
    normalized.replace(user_cap_pos, 5, "User: " + marker_block + " ");
    return normalized;
  }

  const size_t user_pos = normalized.find("user:");
  if (user_pos != std::string::npos) {
    normalized.replace(user_pos, 5, "user: " + marker_block + " ");
    return normalized;
  }

  return marker_block + "\n" + normalized;
}

bool decode_multimodal_prompt(const std::string & prompt) {
  if (g_state.mm_ctx == nullptr) {
    set_error(
        "Multimodal projector is not loaded. Call loadMultimodalProjector first.");
    clear_pending_media();
    return false;
  }

  mtmd_input_chunks * chunks = mtmd_input_chunks_init();
  if (chunks == nullptr) {
    set_error("Failed to allocate multimodal input chunks");
    clear_pending_media();
    return false;
  }

  const std::string normalized_prompt =
      normalize_media_markers(prompt, g_pending_media.size());

  mtmd_input_text input_text {};
  input_text.text = normalized_prompt.c_str();
  const llama_token bos = llama_vocab_bos(g_state.vocab);
  const llama_token eos = llama_vocab_eos(g_state.vocab);
  input_text.add_special = bos != eos && bos != -1;
  input_text.parse_special = true;

  std::vector<const mtmd_bitmap *> bitmaps;
  bitmaps.reserve(g_pending_media.size());
  for (const mtmd_bitmap * bitmap : g_pending_media) {
    bitmaps.push_back(bitmap);
  }

  const int32_t tokenize_rc = mtmd_tokenize(
      g_state.mm_ctx,
      chunks,
      &input_text,
      bitmaps.data(),
      bitmaps.size());

  if (tokenize_rc != 0) {
    if (tokenize_rc == 1) {
      set_error(
          "Multimodal marker count does not match number of provided media parts");
    } else if (tokenize_rc == 2) {
      set_error("Failed to preprocess multimodal media content");
    } else {
      set_error("mtmd_tokenize failed while processing multimodal prompt");
    }
    mtmd_input_chunks_free(chunks);
    clear_pending_media();
    return false;
  }

  llama_pos new_n_past = 0;
  int32_t n_batch = static_cast<int32_t>(llama_n_batch(g_state.ctx));
  if (n_batch <= 0) {
    n_batch = 512;
  }

  const int32_t eval_rc = mtmd_helper_eval_chunks(
      g_state.mm_ctx,
      g_state.ctx,
      chunks,
      0,
      0,
      n_batch,
      true,
      &new_n_past);

  mtmd_input_chunks_free(chunks);
  clear_pending_media();

  if (eval_rc != 0) {
    set_error("mtmd_helper_eval_chunks failed while ingesting multimodal prompt");
    return false;
  }

  return true;
}

llama_sampler * create_sampler(
    const float temp,
    const int32_t top_k,
    const float top_p,
    const float repeat_penalty,
    const char * grammar,
    const uint32_t seed) {
  llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
  llama_sampler * sampler = llama_sampler_chain_init(sparams);
  if (sampler == nullptr) {
    return nullptr;
  }

  if (repeat_penalty != 1.0f) {
    llama_sampler_chain_add(
        sampler,
        llama_sampler_init_penalties(64, repeat_penalty, 0.0f, 0.0f));
  }

  if (top_k > 0) {
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
  }

  if (top_p < 1.0f) {
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
  }

  if (grammar != nullptr && std::strlen(grammar) > 0) {
    llama_sampler * grammar_sampler =
        llama_sampler_init_grammar(g_state.vocab, grammar, "root");
    if (grammar_sampler == nullptr) {
      llama_sampler_free(sampler);
      return nullptr;
    }
    llama_sampler_chain_add(sampler, grammar_sampler);
  }

  llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp));
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));

  return sampler;
}

int32_t begin_generation_impl(
    const char * prompt,
    float temp,
    int32_t top_k,
    float top_p,
    float repeat_penalty,
    const char * grammar,
    uint32_t seed) {
  clear_error();
  g_last_output.clear();
  g_last_piece.clear();

  if (!ensure_loaded()) {
    return -1;
  }

  if (prompt == nullptr) {
    set_error("Prompt is null");
    return -2;
  }

  if (temp < 0.0f) {
    temp = 0.0f;
  }

  if (top_k < 0) {
    top_k = 0;
  }

  if (top_p <= 0.0f || top_p > 1.0f) {
    top_p = 1.0f;
  }

  if (repeat_penalty <= 0.0f) {
    repeat_penalty = 1.0f;
  }

  end_generation_state();
  g_cancel_requested = false;

  llama_memory_clear(llama_get_memory(g_state.ctx), false);

  const std::string prompt_text = prompt;
  if (!g_pending_media.empty()) {
    if (!decode_multimodal_prompt(prompt_text)) {
      return -3;
    }
  } else {
    std::vector<llama_token> prompt_tokens;
    if (!tokenize_text(prompt_text, true, prompt_tokens)) {
      return -3;
    }

    if (!decode_tokens(prompt_tokens)) {
      return -4;
    }
  }

  g_active_sampler =
      create_sampler(temp, top_k, top_p, repeat_penalty, grammar, seed);
  if (g_active_sampler == nullptr) {
    if (grammar != nullptr && std::strlen(grammar) > 0) {
      set_error("Failed to initialize sampler chain (invalid grammar)");
    } else {
      set_error("Failed to initialize sampler chain");
    }
    return -5;
  }

  g_generation_active = true;
  return 0;
}

int32_t next_token_impl() {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (!g_generation_active || g_active_sampler == nullptr) {
    set_error("Generation is not active");
    return -2;
  }

  if (g_cancel_requested) {
    end_generation_state();
    return 0;
  }

  const llama_token token = llama_sampler_sample(g_active_sampler, g_state.ctx, -1);
  if (token == LLAMA_TOKEN_NULL) {
    set_error("Sampler returned LLAMA_TOKEN_NULL");
    end_generation_state();
    return -3;
  }

  if (llama_vocab_is_eog(g_state.vocab, token)) {
    end_generation_state();
    return 0;
  }

  g_last_piece = token_to_piece(token, true);
  g_last_output += g_last_piece;

  llama_token token_for_decode = token;
  const int rc = llama_decode(g_state.ctx, llama_batch_get_one(&token_for_decode, 1));
  if (rc != 0) {
    if (g_cancel_requested) {
      end_generation_state();
      return 0;
    }
    set_error("llama_decode failed while generating tokens");
    end_generation_state();
    return -4;
  }

  return 1;
}

}  // namespace

extern "C" {

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_probe() {
  refresh_backend_probe();
  return g_has_webgpu ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_backends_json() {
  refresh_backend_probe();
  return g_backend_json.c_str();
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_last_error() {
  return g_last_error.c_str();
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_load_model(
    const char * model_path,
    int32_t n_ctx,
    int32_t n_threads,
    int32_t n_gpu_layers) {
  clear_error();
  g_last_output.clear();
  g_cancel_requested = false;

  if (model_path == nullptr || std::strlen(model_path) == 0) {
    set_error("Model path is empty");
    return -1;
  }

  free_runtime();

  llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = n_gpu_layers;
  mparams.use_mmap = false;
  mparams.use_mlock = false;
  mparams.vocab_only = false;

  g_state.model = llama_model_load_from_file(model_path, mparams);
  if (g_state.model == nullptr) {
    set_error("llama_model_load_from_file failed");
    return -2;
  }

  llama_context_params cparams = llama_context_default_params();
  if (n_ctx > 0) {
    cparams.n_ctx = static_cast<uint32_t>(n_ctx);
  }

  if (n_threads > 0) {
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;
  }

  if (cparams.n_batch == 0 || cparams.n_batch > cparams.n_ctx) {
    cparams.n_batch = std::min<uint32_t>(cparams.n_ctx, 1024U);
  }

  if (cparams.n_ubatch == 0 || cparams.n_ubatch > cparams.n_batch) {
    cparams.n_ubatch = std::min<uint32_t>(cparams.n_batch, 512U);
  }

  const bool enable_gpu_ops = n_gpu_layers > 0;
  cparams.offload_kqv = enable_gpu_ops;
  cparams.op_offload = enable_gpu_ops;
  cparams.no_perf = true;

  g_state.ctx = llama_init_from_model(g_state.model, cparams);
  if (g_state.ctx == nullptr) {
    set_error("llama_init_from_model failed");
    free_runtime();
    return -3;
  }

  g_state.vocab = llama_model_get_vocab(g_state.model);
  g_state.n_ctx = llama_n_ctx(g_state.ctx);
  llama_set_abort_callback(g_state.ctx, should_abort_callback, nullptr);

  rebuild_model_metadata_json();
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_mmproj_load(
    const char * mmproj_path) {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (mmproj_path == nullptr || std::strlen(mmproj_path) == 0) {
    set_error("Multimodal projector path is empty");
    return -2;
  }

  clear_pending_media();

  if (g_state.mm_ctx != nullptr) {
    mtmd_free(g_state.mm_ctx);
    g_state.mm_ctx = nullptr;
  }

  mtmd_context_params params = mtmd_context_params_default();
  params.use_gpu = g_has_webgpu;
  params.print_timings = false;
  params.n_threads = llama_n_threads(g_state.ctx);
  if (params.n_threads <= 0) {
    params.n_threads = 1;
  }

  g_state.mm_ctx = mtmd_init_from_file(mmproj_path, g_state.model, params);
  if (g_state.mm_ctx == nullptr) {
    set_error("Failed to load multimodal projector");
    return -3;
  }

  return 0;
}

EMSCRIPTEN_KEEPALIVE void llamadart_webgpu_mmproj_free() {
  clear_pending_media();

  if (g_state.mm_ctx != nullptr) {
    mtmd_free(g_state.mm_ctx);
    g_state.mm_ctx = nullptr;
  }
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_mmproj_supports_vision() {
  if (g_state.mm_ctx == nullptr) {
    return 0;
  }
  return mtmd_support_vision(g_state.mm_ctx) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_mmproj_supports_audio() {
  if (g_state.mm_ctx == nullptr) {
    return 0;
  }
  return mtmd_support_audio(g_state.mm_ctx) ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE void llamadart_webgpu_media_clear_pending() {
  clear_error();
  clear_pending_media();
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_media_add_file(
    const char * media_path) {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (g_state.mm_ctx == nullptr) {
    set_error("Multimodal projector is not loaded");
    return -2;
  }

  if (media_path == nullptr || std::strlen(media_path) == 0) {
    set_error("Media file path is empty");
    return -3;
  }

  mtmd_bitmap * bitmap =
      mtmd_helper_bitmap_init_from_file(g_state.mm_ctx, media_path);
  if (bitmap == nullptr) {
    set_error("Failed to decode media file content");
    return -4;
  }

  g_pending_media.push_back(bitmap);
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_media_add_encoded(
    const uint8_t * bytes,
    int32_t length) {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (g_state.mm_ctx == nullptr) {
    set_error("Multimodal projector is not loaded");
    return -2;
  }

  if (bytes == nullptr || length <= 0) {
    set_error("Encoded media bytes are empty");
    return -3;
  }

  mtmd_bitmap * bitmap = mtmd_helper_bitmap_init_from_buf(
      g_state.mm_ctx,
      bytes,
      static_cast<size_t>(length));
  if (bitmap == nullptr) {
    set_error("Failed to decode encoded media bytes");
    return -4;
  }

  g_pending_media.push_back(bitmap);
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_media_add_rgb(
    uint32_t width,
    uint32_t height,
    const uint8_t * bytes,
    int32_t length) {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (g_state.mm_ctx == nullptr) {
    set_error("Multimodal projector is not loaded");
    return -2;
  }

  if (width == 0 || height == 0 || bytes == nullptr || length <= 0) {
    set_error("Invalid raw RGB media payload");
    return -3;
  }

  const size_t expected = static_cast<size_t>(width) * static_cast<size_t>(height) * 3;
  if (expected != static_cast<size_t>(length)) {
    set_error("Raw RGB bytes do not match width*height*3");
    return -4;
  }

  mtmd_bitmap * bitmap = mtmd_bitmap_init(width, height, bytes);
  if (bitmap == nullptr) {
    set_error("Failed to initialize RGB media bitmap");
    return -5;
  }

  g_pending_media.push_back(bitmap);
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_media_add_audio_f32(
    const float * samples,
    int32_t sample_count) {
  clear_error();

  if (!ensure_loaded()) {
    return -1;
  }

  if (g_state.mm_ctx == nullptr) {
    set_error("Multimodal projector is not loaded");
    return -2;
  }

  if (samples == nullptr || sample_count <= 0) {
    set_error("Audio samples are empty");
    return -3;
  }

  mtmd_bitmap * bitmap =
      mtmd_bitmap_init_from_audio(static_cast<size_t>(sample_count), samples);
  if (bitmap == nullptr) {
    set_error("Failed to initialize audio bitmap");
    return -4;
  }

  g_pending_media.push_back(bitmap);
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_tokenize_to_json(
    const char * text,
    int32_t add_special) {
  clear_error();
  g_last_tokens_json = "[]";

  if (text == nullptr) {
    set_error("Text is null");
    return -1;
  }

  std::vector<llama_token> tokens;
  if (!tokenize_text(text, add_special != 0, tokens)) {
    return -2;
  }

  g_last_tokens_json = serialize_tokens_json(tokens);
  return static_cast<int32_t>(tokens.size());
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_last_tokens_json() {
  return g_last_tokens_json.c_str();
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_detokenize_from_json(
    const char * token_text,
    int32_t special) {
  clear_error();
  g_last_detokenized.clear();

  if (!ensure_loaded()) {
    return -1;
  }

  std::vector<llama_token> tokens;
  parse_token_list(token_text, tokens);

  if (tokens.empty()) {
    return 0;
  }

  g_last_detokenized.reserve(tokens.size() * 4);
  for (const llama_token token : tokens) {
    g_last_detokenized += token_to_piece(token, special != 0);
  }

  return static_cast<int32_t>(g_last_detokenized.size());
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_last_detokenized() {
  return g_last_detokenized.c_str();
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_generate(
    const char * prompt,
    int32_t n_predict,
    float temp,
    int32_t top_k,
    float top_p,
    float repeat_penalty,
    const char * grammar,
    uint32_t seed) {
  if (n_predict <= 0) {
    n_predict = 128;
  }

  const int32_t begin_rc = begin_generation_impl(
      prompt,
      temp,
      top_k,
      top_p,
      repeat_penalty,
      grammar,
      seed);
  if (begin_rc != 0) {
    return begin_rc;
  }

  for (int32_t i = 0; i < n_predict; ++i) {
    const int32_t step_rc = next_token_impl();
    if (step_rc == 0) {
      break;
    }

    if (step_rc < 0) {
      end_generation_state();
      return step_rc;
    }
  }

  end_generation_state();
  return 0;
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_begin_generation(
    const char * prompt,
    float temp,
    int32_t top_k,
    float top_p,
    float repeat_penalty,
    const char * grammar,
    uint32_t seed) {
  return begin_generation_impl(
      prompt,
      temp,
      top_k,
      top_p,
      repeat_penalty,
      grammar,
      seed);
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_next_token() {
  return next_token_impl();
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_last_piece() {
  return g_last_piece.c_str();
}

EMSCRIPTEN_KEEPALIVE void llamadart_webgpu_end_generation() {
  end_generation_state();
}

EMSCRIPTEN_KEEPALIVE void llamadart_webgpu_request_cancel() {
  g_cancel_requested = true;
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_last_output() {
  return g_last_output.c_str();
}

EMSCRIPTEN_KEEPALIVE int32_t llamadart_webgpu_get_context_size() {
  if (g_state.ctx == nullptr) {
    return 0;
  }
  return static_cast<int32_t>(llama_n_ctx(g_state.ctx));
}

EMSCRIPTEN_KEEPALIVE const char * llamadart_webgpu_model_meta_json() {
  return g_model_meta_json.c_str();
}

EMSCRIPTEN_KEEPALIVE void llamadart_webgpu_shutdown() {
  free_runtime();

  if (g_backend_initialized) {
    llama_backend_free();
    g_backend_initialized = false;
  }

  g_has_webgpu = false;
  g_backend_json = "[]";
}

}  // extern "C"

int main() {
  return 0;
}
