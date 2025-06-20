#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG_PREFIX() { echo \"$(date '+%Y-%m-%d %H:%M:%S') [restart_pmta]\"; }
log()   { LOG_PREFIX; echo \" INFO: $*\"; }
error() { LOG_PREFIX; echo \" ERROR: $*\" >&2; exit 1; }

main() {
  log \"重启 PowerMTA 服务\"
  systemctl restart pmta || error \"重启 PowerMTA 失败\"
  systemctl status pmta --no-pager
  log \"PowerMTA 服务已重启\"
}
main \"$@\"

