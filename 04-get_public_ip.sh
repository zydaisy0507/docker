#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [get_public_ip] INFO: $*"
}
error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [get_public_ip] ERROR: $*" >&2
}

# 检测合法 IPv4 格式
is_ipv4() {
  if [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS=. read -r a b c d <<< "$1"
    (( a<256 && b<256 && c<256 && d<256 ))
    return
  fi
  return 1
}

# 从 HTTP 服务获取 IP 并校验
fetch_http() {
  local url=$1 tmp ip
  tmp=$(curl -sS --max-time 10 "$url" || echo "")
  ip=${tmp//[[:space:]]/}
  if is_ipv4 "$ip"; then
    echo "$ip"
  fi
}

main() {
  BASE_DIR="/tmp/pmta-secrets"
  IP_DIR="$BASE_DIR/ip"
  mkdir -p "$IP_DIR"
  chmod 700 "$IP_DIR"

  declare -A counts
  sources=(
    "https://ipv4.icanhazip.com"
    "https://api.ipify.org?format=text"
    "https://ifconfig.co/ip"
  )

  log "开始获取公网 IP"
  for url in "${sources[@]}"; do
    for try in 1 2 3; do
      ip=$(fetch_http "$url")
      if [[ -n "$ip" ]]; then
        counts["$ip"]=$(( ${counts["$ip"]:-0} + 1 ))
        log "来源 $url 第 $try 次成功: $ip"
        break
      else
        log "来源 $url 第 $try 次无效响应"
        sleep $(( try * 2 ))
      fi
    done
  done

  if ((${#counts[@]} == 0)); then
    log "HTTP 源获取失败，尝试本地接口检测"
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')
    if is_ipv4 "$ip"; then
      counts["$ip"]=1
      log "本地接口检测 IP: $ip"
    fi
  fi

  # 选取出现次数最多的 IP
  best_ip=""
  best_count=0
  for ip in "${!counts[@]}"; do
    if (( counts["$ip"] > best_count )); then
      best_ip="$ip"
      best_count=${counts["$ip"]}
    fi
  done

  if [[ -z "$best_ip" ]]; then
    error "未能获取有效公网 IP"
    exit 1
  fi

  echo -n "$best_ip" > "$IP_DIR/public_ip.txt"
  chmod 600 "$IP_DIR/public_ip.txt"
  log "最终选定公网 IP: $best_ip 并保存到 $IP_DIR/public_ip.txt"
}

main "$@"
