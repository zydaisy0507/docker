#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_dns01] INFO: $*"; }
ERR()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_dns01] ERROR: $*" >&2; exit 1; }

main() {
  : "${CF_API_TOKEN:?请设置 CF_API_TOKEN}"
  : "${DOMAIN:?请设置 DOMAIN}"
  : "${ACME_EMAIL:?请设置 ACME_EMAIL}"

  command -v acme.sh &>/dev/null || ERR "acme.sh 未安装"

  export CF_Token="$CF_API_TOKEN"
  if acme.sh --issue --dns dns_cf \
      -d "$DOMAIN" -d "www.$DOMAIN" --accountemail "$ACME_EMAIL" --keylength 2048
  then
    LOG "acme.sh DNS-01 申请成功"
  else
    ERR "acme.sh DNS-01 申请失败"
  fi
}

main "$@"
