#!/bin/bash

# Fails fast on a malformed config file, before anything is generated. The rules live in schema/config.schema.json.
# Run from the repo root (make gen and make gen-go both do this before generating).

set -e

BASE_DIR="$(pwd)"
source "${BASE_DIR}/scripts/bash/lib/node_env.sh"
use_workspace_node "${BASE_DIR}/scripts/nodejs"
node "${BASE_DIR}/scripts/nodejs/packages/config/src/cli.mjs" "${1:-config.json}"
