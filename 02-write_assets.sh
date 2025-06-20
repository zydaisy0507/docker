#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG_PREFIX() { echo "$(date '+%Y-%m-%d %H:%M:%S') [write_assets]"; }
log()   { LOG_PREFIX; echo " INFO: $*"; }
error() { LOG_PREFIX; echo " ERROR: $*" >&2; }

main() {
    local target="/tmp/assets"

    log "开始校验资源目录：$target"
    if [[ ! -d "$target" ]]; then
        error "$target 不存在"
        exit 1
    fi

    # 必须存在的脚本 & 文件
    local files=(
        "$target/scripts/01-system_update.sh"
        "$target/scripts/02-write_assets.sh"
        "$target/scripts/03-gen_dkim.sh"
        "$target/scripts/04-get_public_ip.sh"
        "$target/scripts/05-fetch_zone.sh"
        "$target/scripts/06-update_dns.sh"
        "$target/scripts/07-install_acme.sh"
        "$target/scripts/08-install_pmta.sh"
        "$target/scripts/09-write_configs.sh"
        "$target/scripts/10-configure_firewall.sh"
        "$target/scripts/11-check_ports.sh"
        "$target/scripts/12-restart_pmta.sh"
        "$target/scripts/13-smtp_connectivity.sh"
        "$target/scripts/14-cleanup.sh"
        "$target/deploy.sh"
        "$target/custom-PowerMTA-5.0r8.deb"
    )

    for f in "${files[@]}"; do
        if [[ ! -e "$f" ]]; then
            error "缺失关键文件: $f"
            exit 1
        fi
    done

    log "所有资源文件均已就绪，开始设置脚本可执行权限"
    chmod +x "$target/scripts/"*.sh

    log "资源校验通过，脚本均已可执行"
}

main "$@"

