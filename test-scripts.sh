#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "🔍 一次性测试 assets/scripts 下所有脚本（不按照顺序，只检查能否执行到 main()）"
for script in assets/scripts/*.sh; do
  echo "-----"
  echo "🛠️  测试脚本: $script"
  # 用 -nomain 参数跳过 main() 里面有依赖参数的逻辑，
  # 这里只想看看语法和函数定义有没有大问题
  bash -n "$script" && echo "✅ 语法通过" || { echo "❌ 语法错误"; continue; }

  # 再做一次简单的 -x 执行到 start of main
  echo "🔎 执行到 main 行级跟踪 (SIGPIPE、语法崩溃都能暴露)"
  bash -x "$script" --help >/dev/null 2>&1 && echo "✅ 能执行到 --help" || echo "⚠️ 执行时报错"
done
