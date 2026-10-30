#!/bin/bash

set -e

# nginx in front of an RPC node: publishes its REST, RPC (+ websocket) and gRPC on the node's own ports, with CORS.
# Rendered from templates/configs/nginx.conf, which the Go generator shares.
function generate_nginx_conf() {
  local L_CONF_PATH="${1}"
  local L_NODE_RPC_PORT="${2}"
  local L_NODE_REST_PORT="${3}"
  local L_NODE_GRPC_PORT="${4}"

  sed -e "s/__REST_PORT__/${L_NODE_REST_PORT}/g" \
      -e "s/__RPC_PORT__/${L_NODE_RPC_PORT}/g" \
      -e "s/__GRPC_PORT__/${L_NODE_GRPC_PORT}/g" \
      "${BASE_TEMPLATES_DIR}/configs/nginx.conf" > "${L_CONF_PATH}"
}
