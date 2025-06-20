#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [configure_firewall] INFO: $*"; }
WARN() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [configure_firewall] WARN: $*"; }

main() {
  command -v ufw >/dev/null 2>&1 || { WARN "ufw 未安装，跳过防火墙配置"; return; }

  LOG "启用 UFW（非交互模式）"
  ufw --force enable || WARN "启用 UFW 失败，可能已启用"

  # 永远保留 SSH 访问
  LOG "确保保留 SSH (22)"
  ufw allow 22/tcp || WARN "放行 22 端口失败，可能已放行"

  # 只放行 SMTP 关键端口
  for p in 25 465 587; do
    LOG "放行 SMTP 端口 $p"
    ufw allow ${p}/tcp || WARN "放行 $p 端口失败，可能已放行"
  done

  LOG "重载防火墙规则"
  ufw reload || WARN "reload 失败，可能无需 reload"

  LOG "当前 UFW 状态："
  ufw status numbered
}

main "$@"
