#!/usr/bin/env bash
# 内置 Whisper 模型：从 HuggingFace 拉取指定模型与 tokenizer，
# 放到 AIVideoPlayer/Resources/Models/whisperkit-coreml（git 忽略）。
# 由 Xcode 构建脚本在编译前执行；模型随 App 打包，运行时不下载。
# 仅 Phase 7 翻译用的大模型才由用户在设置页自行选择下载。
#
# 文件清单固化在 scripts/whisperkit-tiny.manifest（不用 HF API，避免 CI 401）。
# 依赖：curl（macOS 自带）。
# 镜像：国内网络不佳时可设 HF_BASE=https://hf-mirror.com 后重新构建。
set -euo pipefail

MODEL_NAME="${WHISPER_MODEL_NAME:-openai_whisper-tiny}"
MODEL_REPO="argmaxinc/whisperkit-coreml"
TOKENIZER_NAME="whisper-${MODEL_NAME#openai_whisper-}"
TOKENIZER_REPO="openai/${TOKENIZER_NAME}"
HF_BASE="${HF_BASE:-https://huggingface.co}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEST_DIR="${PROJECT_ROOT}/AIVideoPlayer/Resources/Models/whisperkit-coreml"
MARKER="${DEST_DIR}/.complete"
MANIFEST="${SCRIPT_DIR}/whisperkit-tiny.manifest"
UA="AIVideoPlayer-Build/1.0"

if [ -f "${MARKER}" ]; then
  echo "Whisper model already bundled (${MODEL_NAME})"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${DEST_DIR}"

echo "Bundling Whisper model: ${MODEL_NAME}（清单：${MANIFEST}）"
while IFS= read -r remote_path; do
  [ -z "${remote_path}" ] && continue
  rel="${remote_path#"${MODEL_NAME}/"}"
  out="${DEST_DIR}/${rel}"
  mkdir -p "$(dirname "${out}")"
  curl -fsSL --connect-timeout 20 --retry 3 -A "${UA}" \
    "${HF_BASE}/${MODEL_REPO}/resolve/main/${remote_path}" \
    -o "${out}" || {
      echo "error: 下载失败 ${remote_path}" >&2
      exit 1
    }
done < "${MANIFEST}"

for f in tokenizer.json tokenizer_config.json config.json; do
  if ! curl -fsSL --connect-timeout 20 --retry 3 -A "${UA}" \
    "${HF_BASE}/${TOKENIZER_REPO}/resolve/main/${f}" \
    -o "${DEST_DIR}/${f}"; then
    echo "warning: 未找到 ${TOKENIZER_REPO}/${f}，继续" >&2
  fi
done

if [ ! -f "${DEST_DIR}/tokenizer.json" ]; then
  echo "error: tokenizer.json 下载失败（${TOKENIZER_REPO}）" >&2
  exit 1
fi

if [ ! -f "${DEST_DIR}/TextDecoder.mlmodelc/metadata.json" ]; then
  echo "error: 模型文件不完整（缺少 TextDecoder.mlmodelc）" >&2
  exit 1
fi

touch "${MARKER}"
echo "Whisper model bundled: ${MODEL_NAME}"
