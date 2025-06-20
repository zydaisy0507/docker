#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [fetch_zone] INFO: $*"
}
error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [fetch_zone] ERROR: $*" >&2
}

main() {
  BASE_DIR="/tmp/pmta-secrets"
  ZONE_DIR="$BASE_DIR/zone"
  mkdir -p "$ZONE_DIR"
  chmod 700 "$ZONE_DIR"

  log "开始获取 Cloudflare Zone ID"

  if [[ -z "${CF_API_TOKEN-}" ]]; then
    error "CF_API_TOKEN 未设置"
    exit 1
  fi
  if [[ -z "${DOMAIN-}" ]]; then
    error "DOMAIN 未设置"
    exit 1
  fi

  # 使用 Cloudflare API 获取 Zone ID
  response=$(curl -sS -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

  success=$(echo "$response" | grep -o '"success":[[:space:]]*true')
  if [[ "$success" != '"success":true' ]]; then
    error "API 调用失败: $response"
    exit 1
  fi

  zone_id=$(echo "$response" | grep -o '"id":"[^"]\+"' | head -1 | cut -d'"' -f4)
  if [[ -z "$zone_id" ]]; then
    error "未能解析到 Zone ID"
    exit 1
  fi

  echo -n "$zone_id" > "$ZONE_DIR/zone_id.txt"
  chmod 600 "$ZONE_DIR/zone_id.txt"
  log "Zone ID: $zone_id，已保存到 $ZONE_DIR/zone_id.txt"
}

main "$@"
