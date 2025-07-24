#!/bin/bash

set -e

function config_hermes() {

  local L_FUND_RPC_INF_FILE="${GENERATED_NETWORK_DIR_UND}/node_rpc1.json"
  local L_GAIAD_RPC_INF_FILE="${GENERATED_NETWORK_DIR_GAIAD}/node_rpc1.json"
  local L_FUND_RPC_IP
  local L_FUND_RPC_PORT
  local L_FUND_GRPC_PORT
  local L_GAIAD_RPC_IP
  local L_GAIAD_RPC_PORT
  local L_GAIAD_GRPC_PORT
  local L_FUND_RPC
  local L_FUND_GRPC
  local L_GAIAD_RPC
  local L_GAIAD_GRPC

  L_FUND_RPC_IP=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.ip')
  L_FUND_RPC_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.rpc_port')
  L_FUND_GRPC_PORT=$(cat < "${L_FUND_RPC_INF_FILE}" | jq -r '.grpc_port')

  L_GAIAD_RPC_IP=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.ip')
  L_GAIAD_RPC_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.rpc_port')
  L_GAIAD_GRPC_PORT=$(cat < "${L_GAIAD_RPC_INF_FILE}" | jq -r '.grpc_port')

  L_FUND_RPC="${L_FUND_RPC_IP}:${L_FUND_RPC_PORT}"
  L_FUND_GRPC="${L_FUND_RPC_IP}:${L_FUND_GRPC_PORT}"
  L_GAIAD_RPC="${L_GAIAD_RPC_IP}:${L_GAIAD_RPC_PORT}"
  L_GAIAD_GRPC="${L_GAIAD_RPC_IP}:${L_GAIAD_GRPC_PORT}"

  mkdir -p "${ASSETS_HERMES_DIR}"

  cp "${BASE_TEMPLATES_DIR}"/configs/hermes_config.toml "${ASSETS_HERMES_DIR}"/config.toml

  sed -i "s/__FUND_RPC__/${L_FUND_RPC}/g" "${ASSETS_HERMES_DIR}"/config.toml
  sed -i "s/__FUND_GRPC__/${L_FUND_GRPC}/g" "${ASSETS_HERMES_DIR}"/config.toml
  sed -i "s/__IBC_GAIAD_RPC__/${L_GAIAD_RPC}/g" "${ASSETS_HERMES_DIR}"/config.toml
  sed -i "s/__IBC_GAIAD_GRPC__/${L_GAIAD_GRPC}/g" "${ASSETS_HERMES_DIR}"/config.toml
  sed -i "s/__FUND_CHAIN_ID__/${CONF_CHAIN_ID}/g" "${ASSETS_HERMES_DIR}"/config.toml
  sed -i "s/__IBC_CHAIN_ID__/${CONF_IBC_CHAIN_ID}/g" "${ASSETS_HERMES_DIR}"/config.toml
}
