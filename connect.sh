#!/usr/bin/env bash
set -u

if (( $# != 4 )); then
  printf 'Usage: %s USER HOST PORT ASKPASS_SCRIPT\n' "$0" >&2
  exit 2
fi

user=$1
host=$2
port=$3
askpass_script=$4

# These values arrive as separate Process arguments, but reject shell control
# characters before using them in this terminal-side script anyway.
if [[ ! "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
  printf 'Invalid SSH username.\n' >&2
  exit 2
fi
if [[ ! "$host" =~ ^[A-Za-z0-9_.:%-]+$ ]]; then
  printf 'Invalid SSH host.\n' >&2
  exit 2
fi
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  printf 'Invalid SSH port.\n' >&2
  exit 2
fi

lookup_host=$host
if [[ "$port" != 22 ]]; then
  lookup_host="[$host]:$port"
fi
first_connection=0
if ! ssh-keygen -F "$lookup_host" >/dev/null 2>&1; then
  first_connection=1
fi

# SSH_ASKPASS_REQUIRE=force lets a saved secret be used without putting the
# password in argv, process listings, shell history, or the terminal command.
# The lookup itself is only enabled when a matching keyring item exists;
# otherwise normal interactive SSH password prompting is preserved.
if command -v secret-tool >/dev/null 2>&1 \
  && secret-tool lookup service omarchy-ssh-lan host "$host" user "$user" port "$port" >/dev/null 2>&1; then
  export OMARCHY_SSH_HOST="$host"
  export OMARCHY_SSH_USER="$user"
  export OMARCHY_SSH_PORT="$port"
  export SSH_ASKPASS="bash $(printf '%q' "$askpass_script")"
  export SSH_ASKPASS_REQUIRE=force
  export DISPLAY="${DISPLAY:-:0}"
fi

printf '\033[1;36mSSH LAN: %s@%s:%s\033[0m\n' "$user" "$host" "$port"
ssh -tt -p "$port" -o ConnectTimeout=5 "$user@$host"
ssh_status=$?

if (( first_connection == 1 && ssh_status == 0 )); then
  printf '\nThis was the first connection to %s. Install your SSH key now? [y/N] ' "$lookup_host"
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    ssh-copy-id -p "$port" "$user@$host"
    copy_status=$?
    if (( copy_status == 0 )); then
      printf '\nSSH key installed. Future connections should not need a password.\n'
    else
      printf '\nssh-copy-id failed (exit %s).\n' "$copy_status"
    fi
  fi
fi

printf '\nPress Enter to close this terminal.\n'
read -r _
exit "$ssh_status"
