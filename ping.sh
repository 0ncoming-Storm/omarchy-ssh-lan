#!/usr/bin/env bash
set -u
set -o pipefail

# Quickshell can inherit a shorter PATH than an interactive terminal. Keep
# standard Arch binary locations available before checking dependencies.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin${PATH:+:$PATH}"

cache_home=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}
log_dir="$cache_home/omarchy-ssh-lan"
log_file="$log_dir/scan.log"
mkdir -p "$log_dir" 2>/dev/null || true
touch "$log_file" 2>/dev/null || true
chmod 700 "$log_dir" 2>/dev/null || true
chmod 600 "$log_file" 2>/dev/null || true

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$log_file" 2>/dev/null || true
}

if (( $# == 0 )); then
  log "ping check start (hosts: 0)"
  exit 0
fi

log "ping check start (hosts: $#)"

# Validate each argument so nothing that looks like an option or contains
# shell/glob metacharacters ever reaches ping.
valid_host() {
  [[ "$1" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

hosts=()
for arg in "$@"; do
  if valid_host "$arg"; then
    hosts+=("$arg")
  else
    log "skip invalid host for ping: $arg"
  fi
done

if (( ${#hosts[@]} == 0 )); then
  log "ping check complete (no valid hosts)"
  exit 0
fi

# Ping up to 8 hosts at once. Each probe waits at most one second, so even a
# large list of dead hosts stays quick. Only hosts that answer are printed,
# one address per line; the QML side maps them back to the stored names.
printf '%s\n' "${hosts[@]}" | xargs -r -P 8 -n 1 bash -c '
  host=$1
  if ping -c 1 -W 1 -q "$host" >/dev/null 2>&1; then
    printf "%s\n" "$host"
  fi
' _

status=$?
log "ping check complete (exit $status)"
exit "$status"