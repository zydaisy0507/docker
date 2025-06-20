#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [check_ports] INFO: $*"; }
WARN() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [check_ports] WARN: $*"; }

main() {
  LOG "检测本地 SMTP 端口状态"
  declare -A ports=(
    [SMTP]=25
    [SMTPS]=465
    [Submission]=587
    [ALT]=2525
  )

  local overall_ok=true
  for name in "${!ports[@]}"; do
    port=${ports[$name]}
    if ss -ltn | grep -q ":$port[[:space:]]"; then
      LOG "$name 端口 $port 已监听"
    else
      WARN "$name 端口 $port 未监听"
      overall_ok=false
    fi
  done

  if $overall_ok; then
    LOG "所有端口监听正常"
  else
    WARN "部分端口未监听，请根据需要手动检查"
  fi
}

main "$@"
