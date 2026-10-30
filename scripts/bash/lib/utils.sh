#!/bin/bash

set -e

function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

function _jq() {
   echo "${1}" | base64 --decode | jq -r "${2}"
}

function init_generated_dirs() {
  #############################
  # Initialise base directories
  #############################

  # Check for and remove generated/assets
  if [ -d "$GENERATED_DIR" ]; then
    rm -rf "${GENERATED_DIR}"
  fi

  mkdir -p "${ASSETS_NODES_FUND_DIR}"
  mkdir -p "${ASSETS_WALLETS_DIR_UND}"
  mkdir -p "${ASSETS_WALLETS_DIR_GAIAD}"
  mkdir -p "${ASSETS_SCRIPTS_DIR}"
  mkdir -p "${ASSETS_TX_RUNNER_DIR}"

  mkdir -p "${GENERATED_NETWORK_DIR_UND}"
  mkdir -p "${GENERATED_NETWORK_DIR_GAIAD}"
  mkdir -p "${GENERATED_NETWORK_DIR_DOCKER}"

  mkdir -p "${TMP_GLOBAL_HOME}"

  # copy scripts to docker assets
  cp "${BASE_TEMPLATES_SCRIPTS_DIR}"/* "${ASSETS_SCRIPTS_DIR}"
}

function init_third_party_dir() {
  if [ ! -d "${THIRD_PARTY_DIR}" ]; then
    mkdir -p "${THIRD_PARTY_DIR}"
    cat >"${THIRD_PARTY_DIR}"/README.md <<EOL
# Third party binaries

The \`bin\` directory contains automatically downloaded binaries
required by the \`generate.sh\` script.
EOL
  fi
}

function generate_network_overview() {
  local L_NET_OVERVIEW_FILE_TMP="${GENERATED_NETWORK_DIR}/overview_tmp.json"
  local L_NET_OVERVIEW_FILE="${GENERATED_NETWORK_DIR}/overview.json"
  local L_FUND_NODES="${GENERATED_NETWORK_DIR_UND}/node_*"
  local L_GAIAD_NODES="${GENERATED_NETWORK_DIR_GAIAD}/node_*"
  local L_HERMES_INF_FILE="${GENERATED_NETWORK_DIR}/hermes.json"

  local L_NODE_NAME=""
  local L_NODE_TYPE=""
  local L_NODE_IP=""
  local L_NODE_P2P_PORT=""
  local L_NODE_RPC_PORT=""
  local L_NODE_REST_PORT=""
  local L_NODE_GRPC_PORT=""
  local L_CNT=0

  local L_NUM_FUND_NODES=$(find ${GENERATED_NETWORK_DIR_UND} -name "node_*" -type f | wc -l)
  local L_NUM_GAIAD_NODES=$(find ${GENERATED_NETWORK_DIR_GAIAD} -name "node_*" -type f | wc -l)

  echo "{" > "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"genesis_version\": \"${CONF_UND_GENESIS_VER}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"upgrade_version\": \"${CONF_UND_UPGRADE_BRANCH}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"fund_chain_id\": \"${CONF_CHAIN_ID}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"gaiad_chain_id\": \"${CONF_IBC_CHAIN_ID}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"fund_upgrade_height\": \"${CONF_UPGRADE_HEIGHT}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"fund_upgrade_plan\": \"${CONF_UPGRADE_PLAN_NAME}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"wallets_dir\": \"${ASSETS_WALLETS_DIR}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"fund_container_prefix\": \"${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}fund\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"gaiad_container_prefix\": \"${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_gaiad\"," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"ibc_denom\": \"${IBC_DENOM}\"," >> "${L_NET_OVERVIEW_FILE_TMP}"

  echo "  \"hermes\": $(cat ${L_HERMES_INF_FILE})," >> "${L_NET_OVERVIEW_FILE_TMP}"

  echo "  \"fund_nodes\": [" >> "${L_NET_OVERVIEW_FILE_TMP}"

  for f in $L_FUND_NODES
  do
    L_CNT=$(awk "BEGIN {print $L_CNT+1}")
    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    L_NODE_IP=$(cat < "${f}" | jq -r ".ip")
    L_NODE_P2P_PORT=$(cat < "${f}" | jq -r ".p2p_port")
    L_NODE_RPC_PORT=$(cat < "${f}" | jq -r ".rpc_port")
    L_NODE_REST_PORT=$(cat < "${f}" | jq -r ".rest_port")
    L_NODE_GRPC_PORT=$(cat < "${f}" | jq -r ".grpc_port")

    echo "    {" >> "${L_NET_OVERVIEW_FILE_TMP}"
    cat >>"${L_NET_OVERVIEW_FILE_TMP}" <<EOL
                 "name": "${L_NODE_NAME}",
                 "type": "${L_NODE_TYPE}",
                 "ip": "${L_NODE_IP}",
                 "p2p_port": "${L_NODE_P2P_PORT}",
                 "rpc_port": "${L_NODE_RPC_PORT}",
                 "rest_port": "${L_NODE_REST_PORT}",
                 "grpc_port": "${L_NODE_GRPC_PORT}",
                 "docker_container": "${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}fund_${L_NODE_NAME}"
EOL
    if [ "$L_CNT" = "$L_NUM_FUND_NODES" ]; then
      echo "    }" >> "${L_NET_OVERVIEW_FILE_TMP}"
    else
      echo "    }," >> "${L_NET_OVERVIEW_FILE_TMP}"
    fi
  done

  echo "  ]," >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "  \"gaiad_nodes\": [" >> "${L_NET_OVERVIEW_FILE_TMP}"

  L_CNT=0

  for f in $L_GAIAD_NODES
  do
    L_CNT=$(awk "BEGIN {print $L_CNT+1}")

    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    L_NODE_IP=$(cat < "${f}" | jq -r ".ip")
    L_NODE_P2P_PORT=$(cat < "${f}" | jq -r ".p2p_port")
    L_NODE_RPC_PORT=$(cat < "${f}" | jq -r ".rpc_port")
    L_NODE_REST_PORT=$(cat < "${f}" | jq -r ".rest_port")
    L_NODE_GRPC_PORT=$(cat < "${f}" | jq -r ".grpc_port")

    echo "    {" >> "${L_NET_OVERVIEW_FILE_TMP}"
    cat >>"${L_NET_OVERVIEW_FILE_TMP}" <<EOL
                 "name": "${L_NODE_NAME}",
                 "type": "${L_NODE_TYPE}",
                 "ip": "${L_NODE_IP}",
                 "p2p_port": "${L_NODE_P2P_PORT}",
                 "rpc_port": "${L_NODE_RPC_PORT}",
                 "rest_port": "${L_NODE_REST_PORT}",
                 "grpc_port": "${L_NODE_GRPC_PORT}",
                 "docker_container": "${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_gaiad_${L_NODE_NAME}"
EOL
    if [ "$L_CNT" = "$L_NUM_GAIAD_NODES" ]; then
      echo "    }" >> "${L_NET_OVERVIEW_FILE_TMP}"
    else
      echo "    }," >> "${L_NET_OVERVIEW_FILE_TMP}"
    fi
  done

  echo "  ]" >> "${L_NET_OVERVIEW_FILE_TMP}"
  echo "}" >> "${L_NET_OVERVIEW_FILE_TMP}"

  cat "${L_NET_OVERVIEW_FILE_TMP}" | jq > "${L_NET_OVERVIEW_FILE}"
  rm "${L_NET_OVERVIEW_FILE_TMP}"
}
