#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [install_pmta] INFO: $*"; }
ERR()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [install_pmta] ERROR: $*" >&2; exit 1; }

# retry <max> <cmd...>
retry() {
  local -i max=$1; shift
  local -i i=1 delay=5
  until "$@"; do
    if (( i >= max )); then return 1; fi
    LOG "第${i}次尝试失败，${delay}s后重试..."
    sleep $delay; ((i++)); delay=$((delay*2))
  done
}

main() {
  PACKAGE="/tmp/assets/assets/PowerMTA-5.0r8.deb"
  PMTA_DIR="/etc/pmta"
  ACME_DIR="/tmp/pmta-secrets/acme"
  KEY="$ACME_DIR/privkey.pem"
  FULL="$ACME_DIR/fullchain.pem"

  # 1. 检查 .deb 包完整性
  [[ -f "$PACKAGE" ]] || ERR "找不到 PowerMTA 安装包：$PACKAGE"
  size=$(stat -c '%s' "$PACKAGE")
  (( size > 100*1024*1024 )) || ERR "安装包大小 (${size} bytes) 太小，可能拷贝不完整"

  # 2. 强制安装 PowerMTA （忽略 preinst 里 license 脚本返回的错误）
  LOG "开始安装 PowerMTA: $PACKAGE"
  dpkg -i "$PACKAGE" || LOG "预安装脚本返回非零，已忽略"
  apt-get update -y
  apt-get install -f -y
  dpkg -i "$PACKAGE" || LOG "再一次 dpkg -i 返回非零，已忽略"

  # 3. 确保 /etc/pmta 存在
  LOG "确保配置目录 $PMTA_DIR"
  mkdir -p "$PMTA_DIR"
  chmod 750 "$PMTA_DIR"

  # 4. 从 .deb 中提取原生模板并覆盖
  LOG "从 DEB 解压并部署原始配置模板"
  TMP_EXTRACT="/tmp/pmta-deb-extract"
  rm -rf "$TMP_EXTRACT"
  mkdir -p "$TMP_EXTRACT"
  dpkg-deb -x "$PACKAGE" "$TMP_EXTRACT"
  cp -f "$TMP_EXTRACT/etc/pmta/config"      "$PMTA_DIR/config"
  cp -f "$TMP_EXTRACT/etc/pmta/config_data.txt" "$PMTA_DIR/config_data.txt"
  chmod 644 "$PMTA_DIR/config" "$PMTA_DIR/config_data.txt"

  # 5. 部署 TLS 证书
  LOG "部署 TLS 证书到 $PMTA_DIR"
  [[ -f "$KEY"  ]] || ERR "私钥不存在: $KEY"
  [[ -f "$FULL" ]] || ERR "证书不存在: $FULL"

  # tls.pem = 私钥 + 站点 cert（第一个证书段）
  { cat "$KEY"; sed -n '1,/END CERTIFICATE/p' "$FULL"; } > "$PMTA_DIR/tls.pem"
  # tls.ca  = fullchain 去掉第一个证书
  sed '1,/END CERTIFICATE/d' "$FULL" > "$PMTA_DIR/tls.ca"
  chmod 600 "$PMTA_DIR/tls.pem" "$PMTA_DIR/tls.ca"

  LOG "PowerMTA 安装完成，配置与证书已部署"
}

main "$@"