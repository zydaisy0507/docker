#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [install_acme] INFO: $*"; }
WARN() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [install_acme] WARN: $*" >&2; }
ERR() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [install_acme] ERROR: $*" >&2; }

retry() {
  local max=$1; shift
  local i=1 delay=5
  until "$@"; do
    if (( i >= max )); then return 1; fi
    LOG "第${i}次失败，${delay}s后重试..."
    sleep $delay
    ((i++))
    delay=$((delay*2))
  done
}

install_deps() {
  # 先安装官方acme.sh
  if ! command -v acme.sh >/dev/null 2>&1; then
    LOG "acme.sh 未检测到，开始安装"
    curl https://get.acme.sh | sh
    export PATH="$HOME/.acme.sh:$PATH"
  fi

  # 其余依赖用apt安装，去掉acme.sh
  local pkgs=(
    curl jq openssl ca-certificates
    bash coreutils grep sed
    socat wget
    certbot lego mailutils
  )

  LOG "开始安装依赖"
  retry 5 apt-get update -y || LOG "apt-get update 失败，继续"
  retry 10 apt-get install -y --no-install-recommends "${pkgs[@]}" || LOG "依赖安装失败，继续"
  LOG "依赖安装完成"
}

install_deps || WARN "依赖安装流程执行完毕，继续申请证书"

main() {
  : "${DOMAIN:?请设置 DOMAIN}"
  : "${HOSTNAME:?请设置 HOSTNAME}"
  : "${ACME_EMAIL:?请设置 ACME_EMAIL}"

  ACME_DIR=/tmp/pmta-secrets/acme
  rm -rf "$ACME_DIR"
  mkdir -p "$ACME_DIR" && chmod 700 "$ACME_DIR"

  LOG "等待 DNS 生效…"

  LOG "开始备用方案调用"
  for script in \
    /root/pmta-deployer/assets/scripts/07-install_acme_http01.sh \
    /root/pmta-deployer/assets/scripts/07-install_acme_dns01.sh \
    /root/pmta-deployer/assets/scripts/07-install_acme_lego.sh
  do
    LOG "尝试运行 ${script##*/}"
    if retry 3 bash "$script"; then
      LOG "${script##*/} 申请成功"
      break
    else
      LOG "${script##*/} 申请失败"
    fi
  done

  if [[ ! -f /tmp/privkey.pem || ! -f /tmp/fullchain.pem ]]; then
    LOG "所有方案失败，生成自签证书"
    openssl req -x509 -nodes -days 3650 \
      -newkey rsa:2048 \
      -keyout /tmp/privkey.pem \
      -out /tmp/fullchain.pem \
      -subj "/CN=$HOSTNAME/O=self-signed"
    LOG "自签证书生成完成"
  fi

  for f in privkey.pem fullchain.pem chain.pem; do
    [[ -f /tmp/$f ]] && { cp /tmp/$f "$ACME_DIR/$f"; chmod 600 "$ACME_DIR/$f"; }
  done

  LOG "证书文件已保存到 $ACME_DIR"
}

main "$@"
