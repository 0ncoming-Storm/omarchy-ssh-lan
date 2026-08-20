#!/usr/bin/env bash
set -u

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

log "scan start (ranges: $#)"

# The shell runs this without sudo. -sT works for an unprivileged user and is
# enough for finding hosts that accept SSH. -R asks nmap for reverse DNS names.
nmap_bin=$(command -v nmap || true)
if [[ -z "$nmap_bin" ]]; then
  log "error: nmap not found (PATH: $PATH)"
  printf '%s\n' 'nmap is required. Install it with: omarchy pkg add nmap' >&2
  printf 'PATH used by the plugin: %s\n' "$PATH" >&2
  exit 1
fi

if (( $# == 0 )); then
  log 'error: no network ranges configured'
  printf '%s\n' 'No network ranges configured. Open the gear menu and add one or more CIDR ranges.' >&2
  exit 1
fi

valid_cidr() {
  local cidr=$1
  local ip=${cidr%/*}
  local prefix=${cidr##*/}
  local part
  local -a octets

  [[ "$cidr" == */* && "$ip" != "$cidr" ]] || return 1
  [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
  (( prefix >= 16 && prefix <= 32 )) || return 1
  IFS=. read -r -a octets <<< "$ip"
  (( ${#octets[@]} == 4 )) || return 1
  for part in "${octets[@]}"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    (( part <= 255 )) || return 1
  done
}

scan_range() {
  local cidr=$1
  local stderr_file
  local output
  local status

  log "scan range: $cidr"
  stderr_file=$(mktemp "${TMPDIR:-/tmp}/omarchy-ssh-lan.XXXXXX")
  output=$("$nmap_bin" -sT -R -T4 --open -p 22 \
    --host-timeout 1500ms --max-retries 1 "$cidr" -oG - 2>"$stderr_file")
  status=$?

  while IFS= read -r line; do
    [[ -n "$line" ]] && log "nmap stderr: $line"
  done < "$stderr_file"
  rm -f "$stderr_file"

  while IFS= read -r line; do
    [[ -n "$line" ]] && log "nmap: $line"
  done <<< "$output"

  if (( status != 0 )); then
    log "scan range failed: $cidr (exit $status)"
  else
    log "scan range complete: $cidr"
  fi

  # Emit host, route type, and reverse-DNS name to the QML process. Names are
  # optional; the UI falls back to the address when no name is available.
  printf '%s\n' "$output" | awk '
    /^Host: / && /22\/open\// {
      name = ""
      openAt = index($0, "(")
      if (openAt > 0) {
        name = substr($0, openAt + 1)
        closeAt = index(name, ")")
        if (closeAt > 0) name = substr(name, 1, closeAt - 1)
      }
      print $2 "\tmanual\t" name
    }
  '
  return "$status"
}

overall_status=0
for cidr in "$@"; do
  if ! valid_cidr "$cidr"; then
    log "skip invalid or unsafe CIDR: $cidr"
    printf 'Skipping invalid or unsafe CIDR (use /16 through /32): %s\n' "$cidr" >&2
    overall_status=1
    continue
  fi

  if ! scan_range "$cidr"; then
    overall_status=1
  fi
done

log "scan complete (exit $overall_status)"
exit "$overall_status"
