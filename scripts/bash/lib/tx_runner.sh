#!/bin/bash

set -e

function generate_tx_runner_dotenv() {
  local L_FUND_RPC_INF_FILE="${GENERATED_NETWORK_DIR_UND}/node_rpc1.json"
  local L_GAIAD_RPC_INF_FILE="${GENERATED_NETWORK_DIR_GAIAD}/node_rpc1.json"
  local L_FUND_RPC_IP
  local L_FUND_RPC_PORT
  local L_FUND_REST_PORT
  local L_GAIAD_RPC_IP
  local L_GAIAD_RPC_PORT
  local L_GAIAD_REST_PORT
  local L_FUND_RPC
  local L_FUND_REST
  local L_GAIAD_RPC
  local L_GAIAD_REST

  L_FUND_RPC_IP=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.ip')
  L_FUND_RPC_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.rest_port')
  L_FUND_REST_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.grpc_port')

  L_GAIAD_RPC_IP=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.ip')
  L_GAIAD_RPC_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.rest_port')
  L_GAIAD_REST_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.grpc_port')

  L_FUND_RPC="${L_FUND_RPC_IP}:${L_FUND_RPC_PORT}"
  L_FUND_REST="${L_FUND_RPC_IP}:${L_FUND_REST_PORT}"
  L_GAIAD_RPC="${L_GAIAD_RPC_IP}:${L_GAIAD_RPC_PORT}"
  L_GAIAD_REST="${L_GAIAD_RPC_IP}:${L_GAIAD_REST_PORT}"

  #ASSETS_TX_RUNNER_DIR
  cat >"${ASSETS_TX_RUNNER_DIR}/.env" <<EOL
FUND_RPC=http://${L_FUND_RPC}
FUND_REST=http://${L_FUND_REST}
GAIAD_RPC=http://${L_GAIAD_RPC}
GAIAD_REST=http://${L_GAIAD_REST}

FUND_CHAIN_ID=${CONF_CHAIN_ID}
IBC_CHAIN_ID=${CONF_IBC_CHAIN_ID}

UPGRADE_PLAN_NAME=${CONF_UPGRADE_PLAN_NAME}
UPGRADE_HEIGHT=${CONF_UPGRADE_HEIGHT}

WALLETS_DIR=wallets
EOL
}

function generate_upgrade_tx() {

  # Upgrade proposal
  cat >"${ASSETS_TX_RUNNER_DIR}/upgrade_proposal_meta.json" <<EOL
  {
   "title": "test upgrade to ${CONF_UPGRADE_PLAN_NAME}"
  }
EOL

  cat >"${ASSETS_TX_RUNNER_DIR}/upgrade_proposal.json" <<EOL
  {
   "messages": [
    {
     "@type": "/cosmos.upgrade.v1beta1.MsgSoftwareUpgrade",
     "authority": "und10d07y265gmmuvt4z0w9aw880jnsr700ja85vs4",
     "plan": {
      "name": "${CONF_UPGRADE_PLAN_NAME}",
      "time": "0001-01-01T00:00:00Z",
      "height": "${CONF_UPGRADE_HEIGHT}",
      "info": "",
      "upgraded_client_state": null
     }
    }
   ],
   "metadata": "ipfs://CID",
   "deposit": "10000000000nund",
   "title": "test upgrade to ${CONF_UPGRADE_PLAN_NAME}",
   "summary": "test upgrade to ${CONF_UPGRADE_PLAN_NAME}"
  }
EOL
}
