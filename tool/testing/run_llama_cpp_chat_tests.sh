#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="${LLAMA_CPP_CHAT_TEST_SOURCE_DIR:-${LLAMA_CPP_SOURCE_DIR:-${repo_root}/.dart_tool/llama_cpp}}"
build_dir="${LLAMA_CPP_CHAT_TEST_BUILD_DIR:-${repo_root}/.dart_tool/llama_cpp_chat_tests}"
include_full="${LLAMA_CPP_CHAT_TEST_INCLUDE_FULL:-0}"
full_verbose="${LLAMA_CPP_CHAT_TEST_FULL_VERBOSE:-0}"

export LLAMA_CPP_SOURCE_DIR="${src_dir}"
"${repo_root}/tool/testing/prepare_llama_cpp_source.sh" >/dev/null

if [[ ! -f "${src_dir}/CMakeLists.txt" ]]; then
  echo "llama.cpp source not found at: ${src_dir}" >&2
  exit 1
fi

echo "[chat-tests] configure: ${build_dir}"
cmake -S "${src_dir}" -B "${build_dir}" \
  -DLLAMA_BUILD_TESTS=ON \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DGGML_CCACHE=OFF \
  -DGGML_OPENMP=OFF

targets=(test-chat-parser test-chat-peg-parser test-chat-template)
if [[ "${include_full}" == "1" ]]; then
  targets+=(test-chat)
fi

echo "[chat-tests] build targets: ${targets[*]}"
cmake --build "${build_dir}" --target "${targets[@]}" --parallel

echo "[chat-tests] running ctest selection"
ctest --test-dir "${build_dir}" --output-on-failure \
  -R '^(test-chat-parser|test-chat-peg-parser|test-chat-template)$'

if [[ "${include_full}" == "1" ]]; then
  echo "[chat-tests] running full test-chat (source-root cwd required)"
  full_test_bin="${build_dir}/bin/test-chat"
  if [[ ! -x "${full_test_bin}" ]]; then
    echo "Missing executable: ${full_test_bin}" >&2
    exit 1
  fi

  if [[ "${full_verbose}" == "1" ]]; then
    (
      cd "${src_dir}"
      "${full_test_bin}"
    )
  else
    full_log="${build_dir}/test-chat.log"
    if ! (
      cd "${src_dir}"
      "${full_test_bin}" >"${full_log}" 2>&1
    ); then
      echo "[chat-tests] full test-chat failed. Log:" >&2
      cat "${full_log}" >&2
      exit 1
    fi
    echo "[chat-tests] full test-chat passed (log: ${full_log})"
  fi
fi
