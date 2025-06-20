#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [write_configs] INFO: $*"; }
ERR()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [write_configs] ERROR: $*" >&2; exit 1; }

: "${DOMAIN:?请设置 DOMAIN}"
: "${HOSTNAME:?请设置 HOSTNAME}"
: "${SMTP_USER:?请设置 SMTP_USER}"
: "${SMTP_PASS:?请设置 SMTP_PASS}"
: "${SELECTOR:?请设置 SELECTOR}"
: "${PUBLIC_IP:?请设置 PUBLIC_IP}"

CONFIG_DIR="/etc/pmta"
TPL_MAIN="$CONFIG_DIR/config"
TPL_DATA="$CONFIG_DIR/config_data.txt"

# 1. 强制复制最新 DKIM 私钥
DKIM_SRC="/tmp/pmta-secrets/dkim/dkim.pem"
DKIM_DST="$CONFIG_DIR/dkim.pem"
LOG "复制 DKIM 私钥：$DKIM_SRC → $DKIM_DST"
if [[ ! -f "$DKIM_SRC" ]]; then
  ERR "未找到 DKIM 私钥：$DKIM_SRC"
fi
mkdir -p "$CONFIG_DIR"
cp -f "$DKIM_SRC" "$DKIM_DST"
chmod 600 "$DKIM_DST"

# 2. 确保模板存在
[[ -f "$TPL_MAIN" ]] || ERR "未找到主配置模板：$TPL_MAIN"
[[ -f "$TPL_DATA" ]] || ERR "未找到副配置模板：$TPL_DATA"

# 3. 写主配置（只替换 HOSTNAME 和 DOMAIN）
LOG "写入 $TPL_MAIN"
{
  sed \
    -e "s/{{HOSTNAME}}/$HOSTNAME/g" \
    -e "s/{{DOMAIN}}/$DOMAIN/g" \
    "$TPL_MAIN"
} > "$TPL_MAIN.tmp" && mv "$TPL_MAIN.tmp" "$TPL_MAIN"
chmod 644 "$TPL_MAIN"

# 4. 写副配置，替换 PUBLIC_IP, DKIM_SELECTOR, DOMAIN, SMTP_USER, SMTP_PASS
LOG "写入 $TPL_DATA"
{
  sed \
    -e "s/{{PUBLIC_IP}}/$PUBLIC_IP/g" \
    -e "s/{{DKIM_SELECTOR}}/$SELECTOR/g" \
    -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{SMTP_USER}}/$SMTP_USER/g" \
    -e "s/{{SMTP_PASS}}/$SMTP_PASS/g" \
    "$TPL_DATA"
} > "$TPL_DATA.tmp" && mv "$TPL_DATA.tmp" "$TPL_DATA"
chmod 644 "$TPL_DATA"

# 5. 重启服务
LOG "重启 pmta.service"
if ! systemctl restart pmta; then
  ERR "重启 pmta.service 失败"
fi

LOG "write_configs 完成"