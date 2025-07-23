#!/bin/bash

set -e

function init_docker() {
  local L_START_IP="${CONF_GLOBAL_DOCKER_IP_START}"
  local L_START_P2P_PORT="${CONF_GLOBAL_DOCKER_P2P_PORT_START}"
  local L_START_RPC_PORT="${CONF_GLOBAL_RPC_PORT_START}"
  local L_START_GRPC_PORT="${CONF_GLOBAL_GRPC_PORT_START}"
  local L_START_REST_PORT="${CONF_GLOBAL_REST_PORT_START}"

  echo "${L_START_IP}" > "${GENERATED_NETWORK_DIR_DOCKER}/ip"
  echo "${L_START_P2P_PORT}" > "${GENERATED_NETWORK_DIR_DOCKER}/p2p_port"
  echo "${L_START_RPC_PORT}" > "${GENERATED_NETWORK_DIR_DOCKER}/rpc_port"
  echo "${L_START_GRPC_PORT}" > "${GENERATED_NETWORK_DIR_DOCKER}/grpc_port"
  echo "${L_START_REST_PORT}" > "${GENERATED_NETWORK_DIR_DOCKER}/rest_port"

  init_docker_compose
}

function init_docker_compose() {
  # initialise docker-compose.yml
  cat >"${GLOBAL_DOCKER_COMPOSE}" <<EOL
services:
EOL
}

function generate_docker_compose_fund_nodes() {

  local L_NODES="${GENERATED_NETWORK_DIR_UND}/node_*"
  local L_NODE_NAME=""
  local L_NODE_TYPE=""
  local L_NODE_IP=""
  local L_NODE_P2P_PORT=""
  local L_NODE_RPC_PORT=""
  local L_NODE_REST_PORT=""
  local L_NODE_GRPC_PORT=""
  local L_DAEMON_RESTART_DELAY="5s"
  local L_DAEMON_SHUTDOWN_GRACE="5s"
  local L_UNSAFE_SKIP_BACKUP="true"
  local L_IS_RPC_NODE="0"

  for f in $L_NODES
  do

    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    L_NODE_IP=$(cat < "${f}" | jq -r ".ip")
    L_NODE_P2P_PORT=$(cat < "${f}" | jq -r ".p2p_port")
    L_NODE_RPC_PORT=$(cat < "${f}" | jq -r ".rpc_port")
    L_NODE_REST_PORT=$(cat < "${f}" | jq -r ".rest_port")
    L_NODE_GRPC_PORT=$(cat < "${f}" | jq -r ".grpc_port")

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
      L_IS_RPC_NODE="1"
    else
      L_IS_RPC_NODE="0"
    fi


    cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL

  ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}fund_${L_NODE_NAME}:
    hostname: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}fund_${L_NODE_NAME}
    build:
      context: .
      dockerfile: docker/und.Dockerfile
      args:
        NODE_NAME: "${L_NODE_NAME}"
        UPGRADE_PLAN_NAME: "${CONF_UPGRADE_PLAN_NAME}"
        UND_GENESIS_VER: "${CONF_UND_GENESIS_VER}"
        IBC_VER: "${CONF_IBC_VER}"
        UND_UPGRADE_BRANCH: "${CONF_UND_UPGRADE_BRANCH}"
        V_PREFIX: "v"
        COSMOVISOR_VER: "${CONF_COSMOVISOR_VER}"
    container_name: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}fund_${L_NODE_NAME}
    environment:
      DAEMON_RESTART_DELAY: "${L_DAEMON_RESTART_DELAY}"
      DAEMON_SHUTDOWN_GRACE: "${L_DAEMON_SHUTDOWN_GRACE}"
      UNSAFE_SKIP_BACKUP: "${L_UNSAFE_SKIP_BACKUP}"
      IS_RPC_NODE: "${L_IS_RPC_NODE}"
    command:  >
      /bin/bash -c "
        cd /root &&
        ./run_node.sh
      "
    networks:
      ${CONF_GLOBAL_DOCKER_NETWORK}:
        ipv4_address: ${L_NODE_IP}
    volumes:
      - ${GLOBAL_DOCKER_OUT_DIR}/${L_NODE_NAME}:/root/out:rw
    ports:
      - "${L_NODE_P2P_PORT}:${L_NODE_P2P_PORT}"
EOL

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
      cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL
      - "${L_NODE_RPC_PORT}:${L_NODE_RPC_PORT}"
      - "${L_NODE_REST_PORT}:${L_NODE_REST_PORT}"
      - "${L_NODE_GRPC_PORT}:${L_NODE_GRPC_PORT}"
EOL
    fi
  done
}

function generate_docker_compose_ibc_nodes() {
  local L_NODES="${GENERATED_NETWORK_DIR_GAIAD}/node_*"
  local L_NODE_NAME=""
  local L_NODE_TYPE=""
  local L_NODE_IP=""
  local L_NODE_P2P_PORT=""
  local L_NODE_RPC_PORT=""
  local L_NODE_REST_PORT=""
  local L_NODE_GRPC_PORT=""
  local L_IS_RPC_NODE="0"

  for f in $L_NODES
  do

    L_NODE_NAME=$(cat < "${f}" | jq -r ".name")
    L_NODE_TYPE=$(cat < "${f}" | jq -r ".type")
    L_NODE_IP=$(cat < "${f}" | jq -r ".ip")
    L_NODE_P2P_PORT=$(cat < "${f}" | jq -r ".p2p_port")
    L_NODE_RPC_PORT=$(cat < "${f}" | jq -r ".rpc_port")
    L_NODE_REST_PORT=$(cat < "${f}" | jq -r ".rest_port")
    L_NODE_GRPC_PORT=$(cat < "${f}" | jq -r ".grpc_port")

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
      L_IS_RPC_NODE="1"
    else
      L_IS_RPC_NODE="0"
    fi

    cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL

  ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_gaiad_${L_NODE_NAME}:
    hostname: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_gaiad_${L_NODE_NAME}
    build:
      context: .
      dockerfile: docker/ibc_gaiad.Dockerfile
      args:
        NODE_NAME: "${L_NODE_NAME}"
        IBC_VER: "${CONF_IBC_VER}"
    container_name: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_gaiad_${L_NODE_NAME}
    environment:
      IS_RPC_NODE: "${L_IS_RPC_NODE}"
    command: >
      /bin/bash -c "
        cd /root &&
        ./run_ibc_gaiad.sh
      "
    networks:
      ${CONF_GLOBAL_DOCKER_NETWORK}:
        ipv4_address: ${L_NODE_IP}
    volumes:
      - ${GLOBAL_DOCKER_OUT_DIR}/ibc_gaiad_${L_NODE_NAME}:/root/out:rw
    ports:
      - "${L_NODE_P2P_PORT}:${L_NODE_P2P_PORT}"
EOL

    if [ "$L_NODE_TYPE" = "$TYPE_NODE_RPC" ]; then
      cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL
      - "${L_NODE_RPC_PORT}:${L_NODE_RPC_PORT}"
      - "${L_NODE_REST_PORT}:${L_NODE_REST_PORT}"
      - "${L_NODE_GRPC_PORT}:${L_NODE_GRPC_PORT}"
EOL
    fi

  done
}

function get_next_docker_ip() {
  local L_IP_SUFFIX=$(cat "${GENERATED_NETWORK_DIR_DOCKER}/ip")
  local L_IP_SUFFIX_NEW
  local L_IP="${CONF_GLOBAL_DOCKER_SUBNET}.${L_IP_SUFFIX}"
  L_IP_SUFFIX_NEW=$(awk "BEGIN {print $L_IP_SUFFIX+1}")
  echo "${L_IP_SUFFIX_NEW}" > "${GENERATED_NETWORK_DIR_DOCKER}/ip"

  echo "${L_IP}"
}

function get_next_docker_port() {
  local L_PORT_TYPE="${1}"
  local L_PORT="0"
  local L_PORT_NEW

  case $L_PORT_TYPE in

    p2p)
      L_PORT="$(cat "${GENERATED_NETWORK_DIR_DOCKER}/p2p_port")"
      L_PORT_NEW=$(awk "BEGIN {print $L_PORT+1}")
      echo "${L_PORT_NEW}" > "${GENERATED_NETWORK_DIR_DOCKER}/p2p_port"
      ;;

    rpc)
      L_PORT="$(cat "${GENERATED_NETWORK_DIR_DOCKER}/rpc_port")"
      L_PORT_NEW=$(awk "BEGIN {print $L_PORT+1}")
      echo "${L_PORT_NEW}" > "${GENERATED_NETWORK_DIR_DOCKER}/rpc_port"
      ;;

    grpc)
      L_PORT="$(cat "${GENERATED_NETWORK_DIR_DOCKER}/grpc_port")"
      L_PORT_NEW=$(awk "BEGIN {print $L_PORT+1}")
      echo "${L_PORT_NEW}" > "${GENERATED_NETWORK_DIR_DOCKER}/grpc_port"
      ;;

    rest)
      L_PORT="$(cat "${GENERATED_NETWORK_DIR_DOCKER}/rest_port")"
      L_PORT_NEW=$(awk "BEGIN {print $L_PORT+1}")
      echo "${L_PORT_NEW}" > "${GENERATED_NETWORK_DIR_DOCKER}/rest_port"
      ;;


    *)
      STATEMENTS
      ;;
  esac

  echo "${L_PORT}"
}

function generate_docker_compose_hermes() {
  local L_FUND_RPC_INF_FILE="${GENERATED_NETWORK_DIR_UND}/node_rpc1.json"
  local L_GAIAD_RPC_INF_FILE="${GENERATED_NETWORK_DIR_GAIAD}/node_rpc1.json"
  local L_HERMES_INF_FILE="${GENERATED_NETWORK_DIR}/hermes.json"
  local L_FUND_RPC_IP
  local L_FUND_RPC_PORT
  local L_FUND_GRPC_PORT
  local L_GAIAD_RPC_IP
  local L_GAIAD_RPC_PORT
  local L_GAIAD_GRPC_PORT

  local L_HERMES_MNEMONIC
  local L_HERMES_IP
  L_HERMES_MNEMONIC=$(cat < "${ASSETS_WALLETS_DIR_UND}/hermes1.json" | jq -r ".mnemonic")
  L_HERMES_IP=$(get_next_docker_ip)

  L_FUND_RPC_IP=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.ip')
  L_FUND_RPC_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.rpc_port')
  L_FUND_GRPC_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.grpc_port')

  L_GAIAD_RPC_IP=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.ip')
  L_GAIAD_RPC_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.rpc_port')
  L_GAIAD_GRPC_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.grpc_port')

  cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL

  ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_hermes:
    hostname: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_hermes
    build:
      context: .
      dockerfile: docker/hermes.Dockerfile
      args:
        MNEMONIC: "${L_HERMES_MNEMONIC}"
        UND_GENESIS_VER: "${CONF_UND_GENESIS_VER}"
        CHAIN_ID: "${CONF_CHAIN_ID}"
        IBC_VER: "${CONF_IBC_VER}"
        IBC_CHAIN_ID: "${CONF_IBC_CHAIN_ID}"
        HERMES_VER: "${CONF_HERMES_VER}"
    container_name: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_hermes
    environment:
      FUND_CHAIN_ID: "${CONF_CHAIN_ID}"
      FUND_RPC_IP: "${L_FUND_RPC_IP}"
      FUND_RPC_PORT: "${L_FUND_RPC_PORT}"
      FUND_GRPC_PORT: "${L_FUND_GRPC_PORT}"
      IBC_CHAIN_ID: "${CONF_IBC_CHAIN_ID}"
      IBC_RPC_IP: "${L_GAIAD_RPC_IP}"
      IBC_RPC_PORT: "${L_GAIAD_RPC_PORT}"
      IBC_GRPC_PORT: "${L_GAIAD_GRPC_PORT}"
    command: >
      /bin/bash -c "
        cd /root &&
        ./run_hermes.sh
      "
    networks:
      ${CONF_GLOBAL_DOCKER_NETWORK}:
        ipv4_address: ${L_HERMES_IP}
    ports:
      - "3000:3000"
      - "3001:3001"
    volumes:
      - ${GLOBAL_DOCKER_OUT_DIR}/hermes:/root/out:rw
EOL

cat>>"${L_HERMES_INF_FILE}" <<EOL
{
  "name": "hermes1",
  "type": "hermes",
  "ip": "${L_HERMES_IP}",
  "prometheus_port": "3001",
  "rest_port": "3000",
  "docker_container": "${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}ibc_hermes"
}
EOL
}

#function generate_docker_compose_proxy() {
#
#  local L_FUND_RPC_INF_FILE
#  local L_PROXY_IP
#  local L_PROXY_PORT
#  local L_FUND_RPC_IP
#  local L_FUND_REST_PORT
#  local L_FUND_REST
#
#  L_PROXY_IP=$(get_next_docker_ip)
#  L_PROXY_PORT=$(get_next_docker_port "rest")
#  L_FUND_RPC_INF_FILE="${GENERATED_NETWORK_DIR_UND}/node_rpc1.json"
#
#  L_FUND_RPC_IP=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.ip')
#  L_FUND_REST_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.rest_port')
#  L_FUND_REST="${L_FUND_RPC_IP}:${L_FUND_REST_PORT}"
#
#  cp "${BASE_TEMPLATES_DIR}"/configs/nginx.conf "${ASSETS_DIR}"/nginx.conf
#
#  sed -i "s/__LISTEN_PORT__/${L_PROXY_PORT}/g" "${ASSETS_DIR}/nginx.conf"
#  sed -i "s/__RPC__/${L_FUND_REST}/g" "${ASSETS_DIR}/nginx.conf"
#
#  cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL
#
#  ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}proxy:
#    hostname: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}proxy
#    container_name: ${CONF_GLOBAL_DOCKER_CONTAINER_PREFIX}proxy
#    build:
#      context: .
#      dockerfile: docker/proxy.Dockerfile
#    networks:
#      ${CONF_GLOBAL_DOCKER_NETWORK}:
#        ipv4_address: ${L_PROXY_IP}
#    ports:
#      - "${L_PROXY_PORT}:${L_PROXY_PORT}"
#    volumes:
#      - ${GLOBAL_DOCKER_OUT_DIR}/proxy:/root/out:rw
#EOL
#}

function set_docker_compose_network() {
  cat >>"${GLOBAL_DOCKER_COMPOSE}" <<EOL

networks:
  ${CONF_GLOBAL_DOCKER_NETWORK}:
    ipam:
      driver: default
      config:
        - subnet: ${CONF_GLOBAL_DOCKER_SUBNET}.0/24

EOL
}
