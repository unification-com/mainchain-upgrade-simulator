#!/bin/bash

set -e

function create_node() {
  local L_BIN="${1}"
  local L_HOME_ROOT="${2}"
  local L_CHAIN_ID="${3}"
  local L_MONIKER="${4}"
  local L_GENERATED_NETWORK_DIR="${5}"
  local L_NODE_TYPE="${6}"
  local L_RPC_PORT="26657"
  local L_REST_PORT="1317"
  local L_GRPC_PORT="9090"
  local L_VALIDATOR_PUBKEY=""
  local L_VALIDATOR_PUBKEY_ESCAPED=""
  local L_NODE_IP
  local L_NODE_P2P_PORT

  L_NODE_IP="$(get_next_docker_ip)"
  L_NODE_P2P_PORT=$(get_next_docker_port "p2p")

  if [ "$L_NODE_TYPE" = "rpc" ]; then
    L_RPC_PORT=$(get_next_docker_port "rpc")
    L_REST_PORT=$(get_next_docker_port "rest")
    L_GRPC_PORT=$(get_next_docker_port "grpc")
  fi

  local L_HOME="${L_HOME_ROOT}/${L_MONIKER}"
  local L_NET_INFO_FILE="${L_GENERATED_NETWORK_DIR}/node_${L_MONIKER}.json"

  local L_TENDERMINT_NODE_ID=""
  local L_P2P_ADDR=""

  init_node "${L_BIN}" "${L_HOME}" "${L_CHAIN_ID}" "${L_MONIKER}"
  L_TENDERMINT_NODE_ID=$(get_node_id "${L_BIN}" "${L_HOME}")
  L_P2P_ADDR="${L_TENDERMINT_NODE_ID}@${L_NODE_IP}:${L_NODE_P2P_PORT}"

  L_VALIDATOR_PUBKEY=$(get_tendermint_validator_pubkey "${L_BIN}" "${L_HOME}")
  L_VALIDATOR_PUBKEY_ESCAPED=$(echo "${L_VALIDATOR_PUBKEY}" | sed 's/"/\\"/g')

  cat >"${L_NET_INFO_FILE}" <<EOL
{
  "name": "${L_MONIKER}",
  "type": "${L_NODE_TYPE}",
  "ip": "${L_NODE_IP}",
  "p2p_port": "${L_NODE_P2P_PORT}",
  "node_id": "${L_TENDERMINT_NODE_ID}",
  "val_pubkey": ${L_VALIDATOR_PUBKEY},
  "val_pubkey_escaped": "${L_VALIDATOR_PUBKEY_ESCAPED}",
  "p2p_addr": "${L_P2P_ADDR}",
  "rpc_port": "${L_RPC_PORT}",
  "rest_port": "${L_REST_PORT}",
  "grpc_port": "${L_GRPC_PORT}"
}
EOL
}

function get_node_id() {
  local L_BIN="${1}"
  local L_HOME="${2}"

  local L_TENDERMINT_NODE_ID=""

  L_TENDERMINT_NODE_ID=$(${L_BIN} tendermint show-node-id --home="${L_HOME}" 2>&1)

  echo "${L_TENDERMINT_NODE_ID}"
}

function get_persistent_peers() {
  local L_GENERATED_NETWORK_DIR="${1}"
  local L_MONIKER="${2}"
  local L_PERSISTENT_PEERS=""
  local L_NODE_ADDR=""
  local L_NODE_NAME=""
  local L_NODE_TYPE=""

  local L_NODES="${L_GENERATED_NETWORK_DIR}/node_*"
  for f in $L_NODES
  do
    L_NODE_ADDR=$(cat < "${f}" | jq -r ".p2p_addr")
    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    if [ "$L_NODE_NAME" != "$L_MONIKER" ] && [ "$L_NODE_TYPE" != "$TYPE_NODE_SEED" ]; then
      L_PERSISTENT_PEERS+="${L_NODE_ADDR},"
    fi
  done

  L_PERSISTENT_PEERS=$(echo "${L_PERSISTENT_PEERS}" | sed 's/\(.*\),/\1/')
  echo "${L_PERSISTENT_PEERS}"
}

function get_seeds() {
  local L_GENERATED_NETWORK_DIR="${1}"
  local L_MONIKER="${2}"
  local L_SEEDS=""
  local L_NODE_ADDR=""
  local L_NODE_NAME=""

  local L_NODES="${L_GENERATED_NETWORK_DIR}/node_*"
  for f in $L_NODES
  do
    L_NODE_ADDR=$(cat < "${f}" | jq -r ".p2p_addr")
    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    if [ "$L_NODE_NAME" != "$L_MONIKER" ] && [ "$L_NODE_TYPE" = "$TYPE_NODE_SEED" ]; then
      L_SEEDS+="${L_NODE_ADDR},"
    fi
  done

  L_SEEDS=$(echo "${L_SEEDS}" | sed 's/\(.*\),/\1/')
  echo "${L_SEEDS}"
}

function configure_nodes() {
  local L_GENERATED_NETWORK_DIR="${1}"
  local L_TMP_GLOBAL_HOME="${2}"
  local L_ASSETS_DIR="${3}"
  local L_MIN_GAS="${4}"
  local L_NODE_NAME=""
  local L_NODE_TYPE=""
  local L_PERSISTENT_PEERS=""
  local L_NODE_CONF_DIR=""
  local L_NODE_P2P_PORT=""
  local L_SEEDS=""
  local L_NODE_IP=""
  local L_NGINX_CONF=""

  local L_NODES="${L_GENERATED_NETWORK_DIR}/node_*"
  for f in $L_NODES
  do
    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    L_NODE_P2P_PORT=$(cat < "${f}" | jq -r ".p2p_port")
    L_NODE_RPC_PORT=$(cat < "${f}" | jq -r ".rpc_port")
    L_NODE_REST_PORT=$(cat < "${f}" | jq -r ".rest_port")
    L_NODE_GRPC_PORT=$(cat < "${f}" | jq -r ".grpc_port")
    L_NODE_IP=$(cat < "${f}" | jq -r ".ip")
    L_NODE_CONF_DIR="${L_ASSETS_DIR}/${L_NODE_NAME}/config"
    L_PERSISTENT_PEERS=$(get_persistent_peers "${L_GENERATED_NETWORK_DIR}" "${L_NODE_NAME}")
    L_SEEDS=$(get_seeds "${L_GENERATED_NETWORK_DIR}" "${L_NODE_NAME}")




    cp "${L_TMP_GLOBAL_HOME}/config/genesis.json" "${L_NODE_CONF_DIR}/genesis.json"

    # -t = str, int, float, bool
    # config.toml
    # p2p.laddr
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/config.toml" p2p.laddr "tcp://0.0.0.0:${L_NODE_P2P_PORT}"
    # p2p.persistent_peers
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/config.toml" p2p.persistent_peers "${L_PERSISTENT_PEERS}"
    # p2p.seeds str
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/config.toml" p2p.seeds "${L_SEEDS}"
    # p2p.addr_book_strict
    ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/config.toml" p2p.addr_book_strict false

    # not sure...
#    ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/config.toml" p2p.allow_duplicate_ip true

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_SEED" ]; then
      # p2p.seed_mode bool
      ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/config.toml" p2p.seed_mode true
    fi

    # TODO - delete. Using proxy instead
#    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
#      # rpc.laddr str "tcp://127.0.0.1:26657"
#      ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/config.toml" rpc.laddr "tcp://${L_NODE_IP}:${L_NODE_RPC_PORT}"
#      ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/config.toml" rpc.experimental_close_on_slow_client true
#    fi

    # app.toml
    # minimum-gas-prices str
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" minimum-gas-prices "${L_MIN_GAS}"

    # pruning str
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" pruning "custom"

    # grpc.enable bool
    ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/app.toml" grpc.enable true

    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" pruning-keep-recent "100"

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
      # pruning-keep-recent str
      ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" pruning-keep-recent "363000"
      # api.enable bool
      ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/app.toml" api.enable true
      # api.swagger bool
      ${TOMLI_BIN} set -i -t bool -f "${L_NODE_CONF_DIR}/app.toml" api.swagger true

      L_NGINX_CONF="${L_ASSETS_DIR}/${L_NODE_NAME}/nginx.conf"
      generate_nginx_conf "${L_NGINX_CONF}" "${L_NODE_RPC_PORT}" "${L_NODE_REST_PORT}" "${L_NODE_GRPC_PORT}"

      # TODO - delete. Using proxy instead
      # api.address str "tcp://localhost:1317"
#      ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" api.address "tcp://${L_NODE_IP}:${L_NODE_REST_PORT}"
      # grpc.address str "localhost:9090"
#      ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" grpc.address "${L_NODE_IP}:${L_NODE_GRPC_PORT}"

    fi

    # pruning-interval str
    ${TOMLI_BIN} set -i -t str -f "${L_NODE_CONF_DIR}/app.toml" pruning-interval "100"

    # state-sync.snapshot-interval int
    # state-sync.snapshot-keep-recent int

  done
}
