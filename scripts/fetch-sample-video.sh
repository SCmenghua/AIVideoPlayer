#!/usr/bin/env bash
# 内置调试示例视频：从 CDN 拉取一个小体积 MP4（约 1 MB），
# 放到 AIVideoPlayer/Resources/Samples/sample.mp4（git 忽略）。
# 由 Xcode 构建脚本在编译前执行；运行时用 Bundle.main 加载，
# 文件缺失时（如构建环境无网络）回退到远程示例 URL。
# 可选环境变量 SAMPLE_VIDEO_URL 更换视频源。
set -euo pipefail

SAMPLE_URL="${SAMPLE_VIDEO_URL:-https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEST_DIR="${PROJECT_ROOT}/AIVideoPlayer/Resources/Samples"
MARKER="${DEST_DIR}/.complete"
UA="AIVideoPlayer-Build/1.0"

if [ -f "${MARKER}" ]; then
  echo "Sample video already bundled"
  exit 0
fi

mkdir -p "${DEST_DIR}"
echo "Bundling sample video: ${SAMPLE_URL}"
if ! curl -fsSL --connect-timeout 20 --retry 3 -A "${UA}" \
  "${SAMPLE_URL}" -o "${DEST_DIR}/sample.mp4"; then
  echo "warning: 示例视频下载失败，运行时回退到远程示例（仅调试入口受影响）" >&2
  exit 0
fi

if [ ! -s "${DEST_DIR}/sample.mp4" ]; then
  echo "warning: 示例视频为空文件，运行时回退到远程示例" >&2
  rm -f "${DEST_DIR}/sample.mp4"
  exit 0
fi

touch "${MARKER}"
echo "Sample video bundled: sample.mp4"
