#!/usr/bin/env bash
# 本地检查通过后提交并推送到 GitHub（SSH）。
set -euo pipefail
msg="${1:?用法: scripts/sync.sh \"提交说明\"}"
cd "$(dirname "$0")/.."
echo "==> swift test"
(cd mac && swift test)
echo "==> commit & push"
git add -A
if git diff --cached --quiet; then
  echo "没有需要提交的改动"
  exit 0
fi
git commit -m "$msg"
git push origin main
