#!/bin/bash

# Fails fast on a malformed config.json, before anything is generated. The rules live in schema/config.schema.json.
validate_config() {
  local L_CONFIG="${1}"
  use_workspace_node "${BASE_DIR}/scripts/nodejs"
  node "${BASE_DIR}/scripts/nodejs/packages/config/src/cli.mjs" "${L_CONFIG}"
}
