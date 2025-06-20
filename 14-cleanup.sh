#!/usr/bin/env bash
# assets/scripts/14-cleanup.sh

# Don’t abort on any error here
set +e
IFS=$'\n\t'

LOG()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cleanup] INFO: $*"; }
WARN() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cleanup] WARN: $*" >&2; }

LOG "Starting cleanup…"

# 1) Remove temp directories
LOG "Removing /tmp/assets"
rm -rf /tmp/assets
LOG "Removing /tmp/pmta-secrets"
rm -rf /tmp/pmta-secrets
LOG "Removing /tmp/pmta-deb-extract"
rm -rf /tmp/pmta-deb-extract

# 2) Define lists of logs to clean
PMTA_LOGS=(
  /var/log/pmta/installer.log
  /var/log/pmta/install.log
)
MAIL_LOGS=(
  /var/log/mail.log
  /var/log/mail.err
  /var/log/mail.info
  /var/log/mail.warn
  /var/log/mail.*.1
)
SYS_LOGS=(
  /var/log/syslog
  /var/log/syslog.*
  /var/log/auth.log
  /var/log/auth.log.*
)

# Helper to remove and recreate a file
clean_file() {
  local path="$1"
  # remove all matching globs
  for f in $path; do
    # if it exists and is a file or symlink
    if [ -e "$f" ]; then
      LOG "Removing log: $f"
      rm -f "$f"
    fi
    # recreate as empty file (mkdir -p parent first)
    mkdir -p "$(dirname "$f")"
    LOG "Recreating empty file: $f"
    : > "$f"
  done
}

# 3) Clean PMTA logs
LOG "Cleaning PMTA logs…"
for p in "${PMTA_LOGS[@]}"; do
  clean_file "$p"
done

# 4) Clean mail logs
LOG "Cleaning mail logs…"
for p in "${MAIL_LOGS[@]}"; do
  clean_file "$p"
done

# 5) Clean system logs
LOG "Cleaning system logs…"
for p in "${SYS_LOGS[@]}"; do
  clean_file "$p"
done

# 6) Echo back SMTP creds (if set)
if [[ -n "${SMTP_USER-}" && -n "${SMTP_PASS-}" ]]; then
  LOG "SMTP credentials used in this run:"
  echo "    SMTP_USER = ${SMTP_USER}"
  echo "    SMTP_PASS = ${SMTP_PASS}"
else
  WARN "SMTP_USER or SMTP_PASS not set; skipping credential echo."
fi

LOG "Cleanup completed."