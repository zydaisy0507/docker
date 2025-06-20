#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_lego] INFO: $*"; }
ERR()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [acme_lego] ERROR: $*" >&2; exit 1; }

main() {
  : "${DOMAIN:?请设置 DOMAIN}"
  : "${ACME_EMAIL:?请设置 ACME_EMAIL}"

  LOG "LEGO HTTP-01 方案"
  lego --email="$ACME_EMAIL" \
    --domains="$DOMAIN" --domains="www.$DOMAIN" \
    --http --http.webroot="/var/www/html" \
    run

  cp ~/.lego/certificates/"$DOMAIN".key     /tmp/privkey.pem
  cp ~/.lego/certificates/"$DOMAIN".crt     /tmp/fullchain.pem
  LOG "lego HTTP-01 完成"
}

main "$@"
