#!/bin/bash

set -e

RUN_WHAT="${1}"

TARGET_SCRIPT=""

case "$RUN_WHAT" in
  "mon" | "monitor")
    TARGET_SCRIPT="monitor" ;;
  "tx" | "tx_runner")
    TARGET_SCRIPT="tx_runner" ;;
  *)
    TARGET_SCRIPT="monitor" ;;
esac

NVM_SH="${HOME}/.nvm/nvm.sh"

# monitor and tx_runner are packages in one yarn workspace - see scripts/nodejs/package.json
cd scripts/nodejs

if test -f "$NVM_SH"; then
  echo "Found ${NVM_SH}"
  source "${NVM_SH}"
  nvm use
fi

yarn workspace "${TARGET_SCRIPT}" start
