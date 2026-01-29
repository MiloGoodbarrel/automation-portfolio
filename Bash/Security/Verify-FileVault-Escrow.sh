#!/bin/bash
set -euo pipefail

# Verify-FileVault-Escrow.sh
# Author: Luis Ramirez
# Checks FileVault status and whether a Personal Recovery Key (PRK) exists.
# Note: Escrow validation must be performed in your MDM (Jamf/Intune).

log() {
  printf "%s %s\n" "[$(date '+%Y-%m-%d %H:%M:%S')]" "$1"
}

if ! command -v fdesetup >/dev/null 2>&1; then
  log "fdesetup not found. This script must run on macOS."
  exit 3
fi

status=$(fdesetup status 2>/dev/null || true)

if [[ "$status" != *"FileVault is On."* ]]; then
  log "FileVault is not enabled."
  exit 2
fi

prk_status=$(fdesetup haspersonalrecoverykey 2>/dev/null || true)

if [[ "$prk_status" == *"true"* ]]; then
  log "FileVault is enabled and a Personal Recovery Key exists."
  exit 0
fi

log "FileVault is enabled but Personal Recovery Key is missing."
exit 1
