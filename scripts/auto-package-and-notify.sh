#!/bin/bash
# 自动化打包和 CI 监控脚本
# 用法: ./scripts/auto-package-and-notify.sh "commit message"

set -e

COMMIT_MSG="${1:-Auto commit}"

echo "======================================"
echo "开始自动化流程"
echo "======================================"

# 1. 添加所有更改
echo "📦 暂存所有更改..."
git add -A

# 2. 提交
echo "💾 提交: $COMMIT_MSG"
git commit -m "$COMMIT_MSG" || {
    echo "⚠️  没有更改需要提交"
    exit 0
}

# 3. 推送
echo "🚀 推送到远程..."
git push origin main

# 4. 等待 CI 启动
echo "⏳ 等待 CI 启动..."
sleep 5

# 5. 获取最新 CI run
RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
echo "🔍 监控 CI run: $RUN_ID"

# 6. 监控 CI
while true; do
  STATUS=$(gh run view "$RUN_ID" --json status,conclusion --jq '{status, conclusion}')
  CONCLUSION=$(echo "$STATUS" | grep -o '"conclusion":"[^"]*"' | cut -d'"' -f4)
  RUN_STATUS=$(echo "$STATUS" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

  echo "$(date '+%H:%M:%S') - Status: $RUN_STATUS"

  if [ "$RUN_STATUS" != "in_progress" ] && [ "$RUN_STATUS" != "queued" ]; then
    echo "======================================"
    if [ "$CONCLUSION" = "success" ]; then
      echo "✅ CI 成功通过！"
      exit 0
    else
      echo "❌ CI 失败"
      echo "查看详情: gh run view $RUN_ID"
      exit 1
    fi
  fi

  sleep 15
done
