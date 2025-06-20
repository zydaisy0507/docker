#!/usr/bin/env bash
set -euo pipefail
LOG()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [smtp_connectivity] INFO: $*"; }
WARN()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [smtp_connectivity] WARN: $*"; }

check_smtp() {
  local port=$1
  LOG "检测本地 SMTP 端口 $port 的连通性"

  # 1) 检查端口监听
  if ! ss -ltn | grep -q ":$port[[:space:]]"; then
    WARN "端口 $port 未监听"
    return
  fi

  # 2) 尝试 SMTP banner
  if ! (echo quit | timeout 5 nc 127.0.0.1 $port 2>/dev/null | grep -qE '^220'); then
    WARN "端口 $port 没有正确响应 220 banner"
    return
  fi

  LOG "端口 $port 正常监听且响应"
}

main() {
  for port in 25 465 587 2525; do
    check_smtp $port
  done
  LOG "SMTP 端口连通性检测完成"
}

main "$@"
