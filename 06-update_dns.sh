#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] [update_dns] INFO: $*"; }
ERR(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] [update_dns] ERROR: $*" >&2; exit 1; }

# 必填环境变量
: "${CF_API_TOKEN:?请设置 CF_API_TOKEN}"
: "${ZONE_ID:?请设置 ZONE_ID}"
: "${DOMAIN:?请设置 DOMAIN}"
: "${HOSTNAME:?请设置 HOSTNAME}"
: "${PUBLIC_IP:?请设置 PUBLIC_IP}"
: "${SELECTOR:?请设置 SELECTOR}"

API="https://api.cloudflare.com/client/v4"
HDR_AUTH="Authorization: Bearer ${CF_API_TOKEN}"
HDR_CT="Content-Type: application/json"

cf_api(){
  local method=$1 url=$2 data=${3-}
  if [[ -n "$data" ]]; then
    curl -s -X "$method" "$url" -H "$HDR_AUTH" -H "$HDR_CT" --data "$data"
  else
    curl -s -X "$method" "$url" -H "$HDR_AUTH" -H "$HDR_CT"
  fi
}

LOG "删除本 zone 下所有 DNS 记录"
page=1 per_page=100
while :; do
  resp=$(cf_api GET "${API}/zones/${ZONE_ID}/dns_records?page=${page}&per_page=${per_page}")
  [[ "$(echo "$resp" | jq -r .success)" == "true" ]] || ERR "列出失败 $(echo "$resp" | jq -c .errors)"
  ids=( $(echo "$resp" | jq -r '.result[].id') )
  [[ ${#ids[@]} -gt 0 ]] || break
  for id in "${ids[@]}"; do
    LOG "删除记录 id=$id"
    cf_api DELETE "${API}/zones/${ZONE_ID}/dns_records/${id}" \
      >/dev/null || LOG "WARN: 删除 id=$id 失败，继续"
  done
  total_pg=$(echo "$resp" | jq -r '.result_info.total_pages')
  (( page++ )) || true
  (( page > total_pg )) && break
done

LOG "开始全量重建 DNS 记录 (TTL=600)"

# A 记录
for name in "$HOSTNAME" "$DOMAIN" "mail.$DOMAIN" "www.$DOMAIN"; do
  LOG "A $name → $PUBLIC_IP"
  cf_api POST "${API}/zones/${ZONE_ID}/dns_records" \
    '{"type":"A","name":"'"$name"'","content":"'"$PUBLIC_IP"'","ttl":600}'
done

# MX 记录
LOG "MX $DOMAIN → mail.$DOMAIN"
cf_api POST "${API}/zones/${ZONE_ID}/dns_records" \
  '{"type":"MX","name":"'"$DOMAIN"'","content":"mail.'"$DOMAIN"'","priority":10,"ttl":600}'

# SPF TXT (注意外层多一对引号)
LOG "TXT SPF $DOMAIN"
cf_api POST "${API}/zones/${ZONE_ID}/dns_records" \
  '{"type":"TXT","name":"'"$DOMAIN"'","content":"\"v=spf1 ip4:'"$PUBLIC_IP"' -all\"","ttl":600}'

# DMARC TXT
LOG "TXT DMARC _dmarc.$DOMAIN"
cf_api POST "${API}/zones/${ZONE_ID}/dns_records" \
  '{"type":"TXT","name":"_dmarc.'"$DOMAIN"'","content":"\"v=DMARC1; p=reject; sp=reject; pct=100; adkim=r; aspf=r; rua=mailto:abuse@'"$DOMAIN"'; ruf=mailto:abuse@'"$DOMAIN"'; ri=86400; fo=1\"","ttl":600}'

# DKIM TXT
LOG "TXT DKIM ${SELECTOR}._domainkey.$DOMAIN"
pubkey=$(< /tmp/pmta-secrets/dkim/pubkey.txt)
dkim_record="v=DKIM1; k=rsa; p=${pubkey}"
cf_api POST "${API}/zones/${ZONE_ID}/dns_records" \
  '{"type":"TXT",
    "name":"'"$SELECTOR"'._domainkey.'"$DOMAIN"'",
    "content":"\"'"$dkim_record"'\"",
    "ttl":600}'

LOG "DNS 全量重建完成"
