#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG_PREFIX() { echo "$(date '+%Y-%m-%d %H:%M:%S') [wait_dns]"; }
log()   { LOG_PREFIX; echo " INFO: $*"; }
error() { LOG_PREFIX; echo " ERROR: $*" >&2; exit 1; }

main() {
  : "${DOMAIN:?未设置 DOMAIN}"
  : "${HOSTNAME:?未设置 HOSTNAME}"
  : "${SELECTOR:?未设置 SELECTOR}"
  : "${PUBLIC_IP:?未设置 PUBLIC_IP}"

  MAX_TRIES=24
  SLEEP=5

  A_NAMES=( "$HOSTNAME" "$DOMAIN" "mail.$DOMAIN" "www.$DOMAIN" )
  MX_EXPECT="mail.$DOMAIN"
  DKIM_NAME="$SELECTOR._domainkey.$DOMAIN"
  DMARC_NAME="_dmarc.$DOMAIN"
  SPF_NAME="$DOMAIN"

  log "初始等待 30s，然后开始检测 DNS 解析生效"
  sleep 30

  for ((i=1; i<=MAX_TRIES; i++)); do
    log "第${i}次检查 DNS 解析"
    ok=true

    # A 记录
    for name in "${A_NAMES[@]}"; do
      mapfile -t ips < <(dig +short "$name" A 2>/dev/null)
      if [[ ! " ${ips[*]} " =~ " $PUBLIC_IP " ]]; then
        log "A 记录 $name 未解析到 $PUBLIC_IP (当前: ${ips[*]:-无})"
        ok=false
      fi
    done

    # MX 记录
    mapfile -t mxs < <(dig +short "$DOMAIN" MX 2>/dev/null | awk '{print $2}' | sed 's/\.$//')
    if [[ ! " ${mxs[*]} " =~ " $MX_EXPECT " ]]; then
      log "MX 记录未解析到 $MX_EXPECT (当前: ${mxs[*]:-无})"
      ok=false
    fi

  # … 上面省略 A/MX 检查 …

  # DKIM TXT：仅做部分匹配
  raw=$(dig +short "$DKIM_NAME" TXT 2>/dev/null | tr -d '"') || raw=""
  dkim_full=$(echo "$raw" | tr -d '[:space:]')

  # 从本地公钥中取一个前缀
  pubkey=$(< /tmp/pmta-secrets/dkim/pubkey.txt)
  prefix=${pubkey:0:24}   # 取前24个字符
  suffix="IDAQAB"

  if [[ "$dkim_full" == v=DKIM1*"$prefix"*"$suffix" ]]; then
    log "DKIM TXT $DKIM_NAME 部分匹配通过"
  else
    log "DKIM TXT $DKIM_NAME 内容不匹配"
    log "  > DNS 返回: ${dkim_full:0:60}…${dkim_full: -20}"
    log "  > 期望包含: v=DKIM1…${prefix}…${suffix}"
    ok=false
  fi

  # … 下面继续 DMARC/SPF 检查 …

    # DMARC TXT
    mapfile -t dmarc < <(dig +short "$DMARC_NAME" TXT 2>/dev/null)
    if [[ ${#dmarc[@]} -eq 0 ]]; then
      log "DMARC TXT $DMARC_NAME 未解析"
      ok=false
    fi

    # SPF TXT
    mapfile -t spf < <(dig +short "$SPF_NAME" TXT 2>/dev/null)
    if [[ ! " ${spf[*]} " =~ "ip4:$PUBLIC_IP" ]]; then
      log "SPF TXT $SPF_NAME 未包含 ip4:$PUBLIC_IP (当前: ${spf[*]:-无})"
      ok=false
    fi

    if $ok; then
      log "DNS 解析验证通过"
      return 0
    fi

    sleep $SLEEP
  done

  error "DNS 解析未在预期时间内生效"
}

main "$@"
