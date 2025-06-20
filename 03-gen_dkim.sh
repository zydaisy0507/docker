#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [gen_dkim] INFO: $*"; }
ERR()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [gen_dkim] ERROR: $*" >&2; exit 1; }

# retry <max> <cmd...>
retry() {
  local -i max=$1; shift
  local -i i=1 delay=5
  until "$@"; do
    if (( i >= max )); then return 1; fi
    LOG "第${i}次失败，${delay}s后重试…"
    sleep $delay
    (( i++ )); delay=$(( delay * 2 ))
  done
  return 0
}

main() {
  LOG "开始生成 DKIM 选择器与密钥"

  BASE_DIR="/tmp/pmta-secrets"
  SECRETS_DIR="$BASE_DIR/dkim"

  # 1) 强制清理旧目录
  if [[ -d "$SECRETS_DIR" ]]; then
    LOG "检测到旧的 DKIM 目录，删除 $SECRETS_DIR"
    rm -rf "$SECRETS_DIR"
  fi

  # 2) 重建目录
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$SECRETS_DIR"

  # 3) 生成或使用 selector
  if [[ -z "${SELECTOR-}" ]]; then
    SELECTOR=$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 18)
    LOG "生成随机 DKIM selector: $SELECTOR"
  else
    LOG "使用已有 DKIM selector: $SELECTOR"
  fi
  echo -n "$SELECTOR" > "$SECRETS_DIR/selector.txt"
  chmod 600 "$SECRETS_DIR/selector.txt"

  # 4) 生成私钥
  retry 3 openssl genrsa -out "$SECRETS_DIR/dkim.pem" 2048 \
    || ERR "openssl genrsa 失败"
  chmod 600 "$SECRETS_DIR/dkim.pem"
  LOG "私钥已保存到 $SECRETS_DIR/dkim.pem"

  # 5) 导出公钥
  retry 3 openssl rsa -in "$SECRETS_DIR/dkim.pem" -pubout -out "$SECRETS_DIR/dkim.pub" \
    || ERR "openssl rsa pubout 失败"
  chmod 600 "$SECRETS_DIR/dkim.pub"

  # 6) 格式化公钥：去掉首尾行，拼一行输出
  sed -n '2,${p}' "$SECRETS_DIR/dkim.pub" | head -n -1 | tr -d '\n' \
    > "$SECRETS_DIR/pubkey.txt"
  chmod 600 "$SECRETS_DIR/pubkey.txt"
  LOG "公钥已格式化并保存到 $SECRETS_DIR/pubkey.txt"

  LOG "DKIM 生成完成，所有文件保存在 $SECRETS_DIR"
}

main "$@"
