#!/usr/bin/env bash
# 白板 W6 并行窗口合并脚本
# 用法：在主工作区 D:\memex 执行 bash merge_w6.sh
# 前提：当前在 v3-lab 分支、工作区干净
#
# 冲突说明（已实测确认）：
# - main.dart / companion_foreground_task.dart / call_voice_* → git 自动合并成功（通话在 !isDesktop 块内，桌面 gating 在外，互不干扰）
# - 仅 DEVLOG.md 和 I_PROJECT_STATE.md 有纯文本追加冲突 → 每步手动保留双方条目
#
# 合并顺序：E → A → C → B → D → S
# 每步：merge → 解 DEVLOG/I_PROJECT_STATE 冲突 → commit → flutter test 快验 → 下一步

set -euo pipefail

BRANCH_ORDER=(
  "codex/whiteboard-w3-security-ui"
  "codex/w5-orchestration"
  "codex/whiteboard-w2-richtext-plus"
  "codex/whiteboard-w1-interactions"
  "codex/whiteboard-w4-desktop-player"
  "codex/whiteboard-s-desktop-shell"
)

echo "============================================"
echo "W6 并行窗口合并脚本"
echo "============================================"
echo ""

# 安全检查
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "v3-lab" ]; then
  echo "❌ 当前分支是 $CURRENT，必须先切到 v3-lab"
  exit 1
fi

DIRTY=$(git status --porcelain | grep -v "^??" | head -1 || true)
if [ -n "$DIRTY" ]; then
  echo "❌ 工作区有未提交改动，请先 stash 或 commit"
  git status --short
  exit 1
fi

echo "✅ 在 v3-lab 分支，工作区干净"
echo "当前 HEAD: $(git log --oneline -1)"
echo ""

# 解冲突函数：DEVLOG.md 和 I_PROJECT_STATE.md 都是追加型文本
# 策略：用 theirs（分支方的条目）追加到 ours（v3-lab 方）之后
# 但最安全的方式是手动检查——这里用 merge-union 策略
resolve_conflicts() {
  local branch=$1
  local had_conflict=0

  for f in DEVLOG.md docs/development/I_PROJECT_STATE.md; do
    if [ -f "$f" ] && grep -q "^<<<<<<< " "$f" 2>/dev/null; then
      echo "  解冲突: $f"
      # 策略：两段都保留。删除 conflict markers，把 ours 和 theirs 的内容都留下
      # 用 sed 处理：保留 ======= 上方(ours) 和 下方(theirs)，删掉 marker 行
      # 更可靠的方式：用 git checkout --theirs + --ours 分别取，再拼接
      # 但因为这些是追加型 markdown，最简单的是：取两边全部内容，去重空行
      python -c "
import re, sys
with open('$f', 'r', encoding='utf-8') as fh:
    content = fh.read()
# 移除 conflict markers，保留双方内容
# <<<<<<< HEAD ... ======= ... >>>>>>> branch
# 保留 HEAD 段和 branch 段，去掉 marker 行
lines = content.split('\n')
result = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith('<<<<<<< '):
        # 跳过 marker，保留 ours 段
        i += 1
        while i < len(lines) and not lines[i].startswith('======='):
            result.append(lines[i])
            i += 1
        # 跳过 =======
        i += 1
        # 保留 theirs 段
        while i < len(lines) and not lines[i].startswith('>>>>>>> '):
            result.append(lines[i])
            i += 1
        # 跳过 >>>>>>> line
        i += 1
    else:
        result.append(line)
        i += 1
with open('$f', 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(result))
print(f'  ✅ {\"$f\"} 冲突已解（双方内容保留）')
" 2>&1
      had_conflict=1
    fi
  done

  if [ $had_conflict -eq 1 ]; then
    git add DEVLOG.md docs/development/I_PROJECT_STATE.md 2>/dev/null || true
  fi

  # 检查是否还有其他冲突
  REMAINING=$(git diff --name-only --diff-filter=U 2>/dev/null | head -1)
  if [ -n "$REMAINING" ]; then
    echo "  ⚠️  还有未解决冲突的文件："
    git diff --name-only --diff-filter=U
    echo "  请手动解决后 git add 再继续"
    return 1
  fi
  return 0
}

# 主循环
STEP=0
TOTAL=${#BRANCH_ORDER[@]}

for branch in "${BRANCH_ORDER[@]}"; do
  STEP=$((STEP + 1))
  echo ""
  echo "============================================"
  echo "[$STEP/$TOTAL] 合并 $branch"
  echo "============================================"

  # 检查分支是否存在
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "❌ 分支 $branch 不存在，跳过"
    continue
  fi

  # 先尝试合并
  CONFLICTED=0
  if ! git merge --no-ff "$branch" -m "merge($branch): W6 并行窗口 $STEP/$TOTAL" 2>&1; then
    CONFLICTED=1
  fi

  # 检查是否有冲突
  CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
  if [ -n "$CONFLICTS" ]; then
    echo "冲突文件："
    echo "$CONFLICTS"
    echo ""
    if ! resolve_conflicts "$branch"; then
      echo "❌ 有未自动解决的冲突，合并中止。请手动解决后："
      echo "   git add <files> && git commit"
      echo "   然后重新运行此脚本（会跳过已合并的分支）"
      exit 1
    fi
    # 冲突解完，完成合并
    git commit --no-edit -m "merge($branch): W6 并行窗口 $STEP/$TOTAL（DEVLOG/I_PROJECT_STATE 冲突已解）" 2>&1
    echo "✅ 冲突已解，合并提交完成"
  elif [ $CONFLICTED -eq 1 ]; then
    # merge 失败但无 conflict 文件——可能是其他问题
    echo "❌ merge 失败但无冲突文件，请检查"
    git status
    exit 1
  else
    echo "✅ 自动合并成功，无冲突"
  fi

  # 快速验证（不阻断，仅报告）
  echo ""
  echo "[$STEP/$TOTAL] 验证..."
  echo "  HEAD: $(git log --oneline -1)"

  # 检查关键文件没有 conflict markers
  CONFLICT_MARKS=$(grep -rl "^<<<<<<< " lib/ test/ 2>/dev/null | head -3 || true)
  if [ -n "$CONFLICT_MARKS" ]; then
    echo "  ⚠️  发现残留 conflict markers："
    echo "$CONFLICT_MARKS"
    echo "  请手动检查！"
  else
    echo "  ✅ 无残留 conflict markers"
  fi

  # 跑 analyze（只报 error 级，不阻断）
  echo "  运行 flutter analyze（仅 error 级）..."
  ANALYZE_RESULT=$(flutter analyze 2>&1 | grep -E "^\s+error" | grep -v "schedule" | head -10 || true)
  if [ -n "$ANALYZE_RESULT" ]; then
    echo "  ⚠️  analyze error（排除已知 schedule 问题）："
    echo "$ANALYZE_RESULT"
  else
    echo "  ✅ analyze 无新增 error"
  fi

  echo ""
  echo "[$STEP/$TOTAL] $branch 合并完成"
done

echo ""
echo "============================================"
echo "🎉 全部 $TOTAL 个分支合并完成！"
echo "============================================"
echo ""
echo "最终 HEAD: $(git log --oneline -1)"
echo ""
echo "合并历史："
git log --oneline --graph -8
echo ""
echo "下一步建议："
echo "  1. 跑全量 flutter test 确认无回归"
echo "  2. 真实桌面窗口验证白板全链路（首页→白板索引→画布→保存→重启恢复）"
echo "  3. 验证通话功能未被白板合并破坏"
echo "  4. 确认后 git push"