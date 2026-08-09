#!/usr/bin/env bash
# 内置 Whisper 模型：从 HuggingFace 拉取指定模型与 tokenizer，
# 放到 AIVideoPlayer/Resources/Models/whisperkit-coreml（git 忽略）。
# 由 Xcode 构建脚本在编译前执行；模型随 App 打包，运行时不下载。
# 仅 Phase 7 翻译用的大模型才由用户在设置页自行选择下载。
#
# 依赖：curl、jq（macOS 自带 curl；GitHub Actions macOS runner 自带 jq）。
set -euo pipefail

MODEL_NAME="${WHISPER_MODEL_NAME:-openai_whisper-tiny}"
MODEL_REPO="argmaxinc/whisperkit-coreml"
TOKENIZER_REPO="openai/${MODEL_NAME#openai_whisper-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEST_DIR="${PROJECT_ROOT}/AIVideoPlayer/Resources/Models/whisperkit-coreml"
MARKER="${DEST_DIR}/.complete"

if [ -f "${MARKER}" ]; then
  echo "Whisper model already bundled (${MODEL_NAME})"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${DEST_DIR}"

echo "Fetching Whisper model file list: ${MODEL_REPO}/${MODEL_NAME}"
curl -fsSL --retry 3 \
  "https://huggingface.co/api/models/${MODEL_REPO}/tree/main/${MODEL_NAME}?recursive=true" \
  -o "${TMP_DIR}/listing.json"

jq -r '.[] | select(.type == "file") | .path' "${TMP_DIR}/listing.json" |
while IFS= read -r remote_path; do
  rel="${remote_path#"${MODEL_NAME}/"}"
  out="${DEST_DIR}/${rel}"
  mkdir -p "$(dirname "${out}")"
  curl -fsSL --retry 3 \
    "https://huggingface.co/${MODEL_REPO}/resolve/main/${remote_path}" \
    -o "${out}" || {
      echo "error: 下载失败 ${remote_path}" >&2
      exit 1
    }
done

for f in tokenizer.json tokenizer_config.json config.json; do
  if ! curl -fsSL --retry 3 \
    "https://huggingface.co/${TOKENIZER_REPO}/resolve/main/${f}" \
    -o "${DEST_DIR}/${f}"; then
    echo "warning: 未找到 ${TOKENIZER_REPO}/${f}，继续" >&2
  fi
done

if [ ! -f "${DEST_DIR}/tokenizer.json" ]; then
  echo "error: tokenizer.json 下载失败（${TOKENIZER_REPO}）" >&2
  exit 1
fi

touch "${MARKER}"
echo "Whisper model bundled: ${MODEL_NAME}"
