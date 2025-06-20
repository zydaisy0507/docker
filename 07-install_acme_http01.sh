#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_http01] INFO: $*"; }
ERR()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_http01] ERROR: $*" >&2; exit 1; }

main() {
  : "${DOMAIN:?请设置 DOMAIN}"
  : "${ACME_EMAIL:?请设置 ACME_EMAIL}"

  LOG "HTTP-01 方案：certbot standalone"
  certbot certonly --non-interactive --agree-tos \
    --email "$ACME_EMAIL" --standalone \
    -d "$DOMAIN" -d "www.$DOMAIN"
  LOG "certbot HTTP-01 完成"
}

main "$@"
