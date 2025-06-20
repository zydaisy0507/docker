#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log()   { echo "$(date '+%F %T') [INFO] $*"; }
warn()  { echo "$(date '+%F %T') [WARN] $*" >&2; }
error() { echo "$(date '+%F %T') [ERROR] $*" >&2; exit 1; }

clean_apt_locks() {
  log "清理 apt 锁文件和残留进程"
  sudo fuser -k /var/lib/dpkg/lock || true
  sudo fuser -k /var/lib/apt/lists/lock || true
  sudo fuser -k /var/lib/dpkg/lock-frontend || true
  sudo rm -f /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend || true
  sudo dpkg --configure -a || true
}

retry_cmd() {
  local max_retries=$1
  shift
  local count=0
  until "$@"; do
    count=$((count+1))
    warn "命令 \"$*\" 第 $count 次失败，3秒后重试..."
    sleep 3
    if (( count >= max_retries )); then
      warn "重试次数达到 $max_retries，继续尝试..."
      count=0
    fi
  done
}

update_sources() {
  log "开始更新软件源"
  retry_cmd 5 sudo apt-get update -y
  log "软件源更新完成"
}

install_dep() {
  local dep=$1
  log "开始安装依赖：$dep"
  retry_cmd 10 sudo apt-get install -y --no-install-recommends "$dep"
  log "依赖 $dep 安装成功"
}

check_dependencies() {
  log "开始检测关键依赖"
  local deps=("certbot" "lego" "curl" "openssl" "acme.sh" "jq" "ufw" "mailutils" "wget" "socat")
  local missing=()
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "依赖 $cmd 未检测到"
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    warn "检测到缺失依赖: ${missing[*]}"
    return 1
  else
    log "所有关键依赖检测通过"
    return 0
  fi
}

main() {
  clean_apt_locks
  update_sources

  DEPS=(
    libc6 libssl-dev curl jq openssl
    mailutils ufw dpkg-dev gzip ca-certificates
    certbot lego socat wget
  )

  for dep in "${DEPS[@]}"; do
    install_dep "$dep"
  done

  # acme.sh 是脚本安装，判断是否安装了，没有则安装
  if ! command -v acme.sh >/dev/null 2>&1; then
    log "acme.sh 未检测到，开始安装"
    curl https://get.acme.sh | bash
    export PATH="$HOME/.acme.sh/:$PATH"
    if ! command -v acme.sh >/dev/null 2>&1; then
      error "acme.sh 安装失败"
    fi
    log "acme.sh 安装完成"
  else
    log "acme.sh 已安装"
  fi

  # 检测依赖，缺失就重装，直到通过
  until check_dependencies; do
    warn "依赖检测未通过，重新安装缺失依赖"
    update_sources
    for dep in "${DEPS[@]}"; do
      install_dep "$dep"
    done
    # 重新安装 acme.sh
    if ! command -v acme.sh >/dev/null 2>&1; then
      log "acme.sh 未检测到，重新安装"
      curl https://get.acme.sh | bash
      export PATH="$HOME/.acme.sh/:$PATH"
      if ! command -v acme.sh >/dev/null 2>&1; then
        error "acme.sh 重新安装失败"
      fi
    fi
  done

  log "系统更新及依赖安装检测全部完成"
}

# 避免 needrestart 阻塞
export NEEDRESTART_MODE=a

# 结束脚本前强制退出
log "安装流程全部完成，退出"
exit 0
