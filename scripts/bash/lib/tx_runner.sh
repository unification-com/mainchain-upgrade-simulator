#!/bin/bash

set -e

# The upgrade proposal the tx runner submits, rendered from templates/configs/upgrade_proposal.json (shared with the
# Go generator).
function generate_upgrade_tx() {
  sed -e "s/__PLAN_NAME__/${CONF_UPGRADE_PLAN_NAME}/g" \
      -e "s/__UPGRADE_HEIGHT__/${CONF_UPGRADE_HEIGHT}/g" \
      "${BASE_TEMPLATES_DIR}/configs/upgrade_proposal.json" > "${ASSETS_TX_RUNNER_DIR}/upgrade_proposal.json"
}
