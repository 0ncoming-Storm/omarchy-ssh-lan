#!/usr/bin/env bash
set -u

if ! command -v secret-tool >/dev/null 2>&1; then
  exit 1
fi

exec secret-tool lookup \
  service omarchy-ssh-lan \
  host "${OMARCHY_SSH_HOST:-}" \
  user "${OMARCHY_SSH_USER:-}" \
  port "${OMARCHY_SSH_PORT:-22}" 2>/dev/null
