#!/bin/bash

set -e

RUN_WHAT="${1}"

TARGET_SCRIPT=""

case "$RUN_WHAT" in
  "mon" | "monitor")
    TARGET_SCRIPT="monitor" ;;
  "tx" | "tx_runner")
    TARGET_SCRIPT="tx_runner" ;;
  "verify")
    TARGET_SCRIPT="verify" ;;
  *)
    TARGET_SCRIPT="monitor" ;;
esac

# monitor and tx_runner are packages in one yarn workspace - see scripts/nodejs/package.json
source scripts/bash/lib/node_env.sh
cd scripts/nodejs
use_workspace_node .

yarn --silent workspace "${TARGET_SCRIPT}" run --silent start
