#!/bin/bash

# Selects the Node version pinned for the scripts/nodejs yarn workspace and checks its dependencies are installed.
# Shared by generate.sh (config validation) and run_nodejs.sh (monitor and tx runner).
use_workspace_node() {
  local L_WORKSPACE_DIR="${1}"
  local L_NODE_VERSION
  L_NODE_VERSION=$(cat "${L_WORKSPACE_DIR}/.nvmrc")
  local L_NVM_SH="${HOME}/.nvm/nvm.sh"

  if test -f "${L_NVM_SH}"; then
    source "${L_NVM_SH}"
    nvm use "${L_NODE_VERSION}"
  fi

  if ! command -v node > /dev/null; then
    echo "node not found - install Node ${L_NODE_VERSION} (see README section 2)"
    exit 1
  fi

  if ! test -d "${L_WORKSPACE_DIR}/node_modules"; then
    echo "Node dependencies are not installed. Run: cd scripts/nodejs && nvm use && yarn install"
    exit 1
  fi
}
