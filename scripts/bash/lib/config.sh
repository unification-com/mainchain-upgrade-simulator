#!/bin/bash

set -e

#############
# Directories
#############

# Template scripts etc.
BASE_TEMPLATES_DIR="${BASE_DIR}/templates"
BASE_TEMPLATES_SCRIPTS_DIR="${BASE_TEMPLATES_DIR}/scripts"

# Generated assets
GENERATED_DIR="${BASE_DIR}/generated"
GENERATED_NETWORK_DIR="${GENERATED_DIR}/network"
GENERATED_NETWORK_DIR_UND="${GENERATED_NETWORK_DIR}/und"
GENERATED_NETWORK_DIR_GAIAD="${GENERATED_NETWORK_DIR}/gaiad"
GENERATED_NETWORK_DIR_DOCKER="${GENERATED_NETWORK_DIR}/docker"

ASSETS_DIR="${GENERATED_DIR}/assets"
ASSETS_SCRIPTS_DIR="${ASSETS_DIR}/scripts"
ASSETS_WALLETS_DIR="${ASSETS_DIR}/wallets"
ASSETS_WALLETS_DIR_UND="${ASSETS_WALLETS_DIR}/und"
ASSETS_WALLETS_DIR_GAIAD="${ASSETS_WALLETS_DIR}/gaiad"
ASSETS_NODES_FUND_DIR="${ASSETS_DIR}/fund_net"
ASSETS_NODES_GAIAD_DIR="${ASSETS_DIR}/gaiad_net"
ASSETS_HERMES_DIR="${ASSETS_DIR}/hermes"
ASSETS_TX_RUNNER_DIR="${ASSETS_DIR}/tx_runner"

# Tmp dirs
TMP_DIR="${GENERATED_DIR}/tmp"
TMP_GLOBAL_HOME="${TMP_DIR}/GLOBAL"
TMP_GLOBAL_UND_HOME="${TMP_GLOBAL_HOME}/.und_mainchain"
TMP_GLOBAL_GAID_HOME="${TMP_GLOBAL_HOME}/.gaiad"

# Docker specific
DOCKERFILES="${BASE_DIR}/docker"
GLOBAL_DOCKER_COMPOSE="${BASE_DIR}/docker-compose.yml"
GLOBAL_DOCKER_OUT_DIR="${GENERATED_DIR}/docker_logs"

# Third party binaries
THIRD_PARTY_DIR="${BASE_DIR}/third_party"
BIN_DIR="${THIRD_PARTY_DIR}/bin"

# Node Types & Prefixes
TYPE_NODE_VALIDATOR="validator"
TYPE_NODE_SENTRY="sentry"
TYPE_NODE_SEED="seed"
TYPE_NODE_RPC="rpc"
PREFIX_NODE_VALIDATOR="${TYPE_NODE_VALIDATOR}"
PREFIX_NODE_SENTRY="${TYPE_NODE_SENTRY}"
PREFIX_NODE_SEED="${TYPE_NODE_SEED}"
PREFIX_NODE_RPC="${TYPE_NODE_RPC}"

TYPE_WALLET_ENTERPRISE="enterprise"
TYPE_WALLET_IBC="ibc"
TYPE_WALLET_HERMES="hermes"
TYPE_WALLET_VALIDATOR="validator"
TYPE_WALLET_WRKCHAIN="wrkchain"
TYPE_WALLET_BEACON="beacon"
TYPE_WALLET_TEST="test"
TYPE_WALLET_PAYMENT_STREAM="stream"
TYPE_WALLET_PAYMENT_STREAM_SENDER="stream_sender"
TYPE_WALLET_PAYMENT_STREAM_RECEIVER="stream_receiver"

##################
# load config.json
##################

# FUND
CONF_CHAIN_ID=$(get_conf ".apps.und.chain_id")
CONF_UND_GENESIS_VER=$(get_conf ".apps.und.genesis.version")
CONF_UPGRADE_HEIGHT=$(get_conf ".apps.und.upgrade.upgrade_height")
CONF_UPGRADE_PLAN_NAME=$(get_conf ".apps.und.upgrade.upgrade_plan_name")
CONF_UND_UPGRADE_BRANCH=$(get_conf ".apps.und.upgrade.branch")
CONF_NUM_VALIDATORS=$(get_conf ".apps.und.nodes.num_validators")
CONF_NUM_SENTRIES=$(get_conf ".apps.und.nodes.num_sentries")
CONF_NUM_SEEDS=$(get_conf ".apps.und.nodes.num_seeds")
CONF_NUM_RPCS=$(get_conf ".apps.und.nodes.num_rpcs")
CONF_MIN_STAKE=$(get_conf ".apps.und.staking.min_stake")
CONF_MAX_STAKE=$(get_conf ".apps.und.staking.max_stake")
CONF_SMALL_MIN_STAKE=$(get_conf ".apps.und.staking.small_min_stake")
CONF_SMALL_MAX_STAKE=$(get_conf ".apps.und.staking.small_max_stake")
CONF_ACCOUNT_START_NUND=$(get_conf ".apps.und.accounts.nund")
CONF_NUM_ENT_SIGNERS=$(get_conf ".apps.und.accounts.num_ent_signers")
CONF_NUM_ENT_ACCEPTS=$(get_conf ".apps.und.accounts.num_ent_accepts")
CONF_NUM_WRKCHAINS=$(get_conf ".apps.und.accounts.num_wrhchains")
CONF_NUM_BEACONS=$(get_conf ".apps.und.accounts.num_beacons")
CONF_NUM_TEST_ACCS=$(get_conf ".apps.und.accounts.num_tests")
CONF_NUM_PAYMENT_STREAMS=$(get_conf ".apps.und.accounts.payment_streams")
STORAGE_PURCHASE=$(get_conf ".apps.und.accounts.storage_purchase")
ENT_PO_AMOUNT=$(get_conf ".apps.und.accounts.ent_po_amount")
GENESIS_TIME=$(get_conf ".apps.und.genesis_time")
CONF_VAL_STAKE_OVERRIDES=$(get_conf ".apps.und.staking.stake_overrides")
CONF_ACC_OBJ=$(get_conf ".apps.und.accounts")
CONF_STATIC_ACCOUNTS=$(get_conf ".apps.und.accounts.static")

# IBC
CONF_IBC_CHAIN_ID=$(get_conf ".apps.ibc.chain_id")
CONF_IBC_VER=$(get_conf ".apps.ibc.version")
CONF_HERMES_VER=$(get_conf ".apps.ibc.hermes_version")
CONF_NUM_IBC_ACCOUNTS=$(get_conf ".apps.ibc.accounts.num_ibc_accounts")
CONF_IBC_ACC_OBJ=$(get_conf ".apps.ibc.accounts")
CONF_IBC_STATIC_ACCOUNTS=$(get_conf ".apps.ibc.accounts.static")

# Cosmovisor
CONF_COSMOVISOR_VER=$(get_conf ".apps.cosmovisor.version")

# Docker
CONF_GLOBAL_DOCKER_SUBNET=$(get_conf ".docker.network.subnet")
CONF_GLOBAL_DOCKER_IP_START=$(get_conf ".docker.network.ip_start")
CONF_GLOBAL_DOCKER_P2P_PORT_START=$(get_conf ".docker.network.p2p_port_start")
CONF_GLOBAL_RPC_PORT_START=$(get_conf ".docker.network.rpc_port_start")
CONF_GLOBAL_REST_PORT_START=$(get_conf ".docker.network.rest_port_start")
CONF_GLOBAL_GRPC_PORT_START=$(get_conf ".docker.network.grpc_port_start")
CONF_GLOBAL_DOCKER_CONTAINER_PREFIX=$(get_conf ".docker.container_prefix")
CONF_GLOBAL_DOCKER_NETWORK="${CONTAINER_PREFIX}up_sim_network"

# Binaries required to generate genesis/accounts etc.
UND_BIN="${BIN_DIR}/und_${CONF_UND_GENESIS_VER}"
GAIAD_BIN="${BIN_DIR}/gaiad_${CONF_IBC_VER}"
V_PREFIX="v"
TOMLI_BIN="${BIN_DIR}/tomli_v0.3.0"
HERMES_BIN="${BIN_DIR}/hermes_${CONF_HERMES_VER}"

IBC_DENOM="ibc/D6CFF2B192E06AFD4CD78859EA7CAD8B82405959834282BE87ABB6B957939618"

###########################
# Config specific functions
###########################

function get_conf() {
  local P=${1}
  cat < "${CONFIG}" | jq -r "${P}"
}
