#!/bin/bash

set -e

BASE_DIR="$(pwd)"
CONFIG="${BASE_DIR}/config.json"

if ! test -f "$CONFIG"; then
  echo "config.json not found. Exiting"
  exit 1
fi

function get_conf() {
  local P=${1}
  cat < "${CONFIG}" | jq -r "${P}"
}

function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }

#############
# Directories
#############

BASE_TEMPLATES_DIR="${BASE_DIR}/templates"
BASE_SCRIPTS_DIR="${BASE_TEMPLATES_DIR}/scripts"
TMP_DIR="${BASE_DIR}/tmp"
TX_DIR="${TMP_DIR}/txs"
ASSETS_DIR="${BASE_DIR}/generated/assets"
ASSETS_SCRIPTS_DIR="${ASSETS_DIR}/scripts"
ASSET_KEYS_DIR_UND="${ASSETS_DIR}/wallet_keys/und"
ASSET_KEYS_DIR_SIMD="${ASSETS_DIR}/wallet_keys/simd"
ASSETS_TXS_DIR="${ASSETS_DIR}/txs"
DOCKER_OUT_DIR="${BASE_DIR}/out"
NODE_ASSETS_DIR="${ASSETS_DIR}/fund_net"
GENERATED_NETWORK="${TMP_DIR}/network.txt"
DOCKER_COMPOSE="${BASE_DIR}/docker-compose.yml"
GLOBAL_TMP_HOME="${TMP_DIR}/GLOBAL"
GLOBAL_TMP_UND_HOME="${TMP_DIR}/GLOBAL/.und_mainchain"
THIRD_PARTY_DIR="${BASE_DIR}/third_party"
BIN_DIR="${THIRD_PARTY_DIR}/bin"

##################
# load config.json
##################

# FUND
CHAIN_ID=$(get_conf ".apps.und.chain_id")
UND_GENESIS_VER=$(get_conf ".apps.und.genesis.version")
UPGRADE_HEIGHT=$(get_conf ".apps.und.upgrade.upgrade_height")
UPGRADE_PLAN_NAME=$(get_conf ".apps.und.upgrade.upgrade_plan_name")
UND_UPGRADE_BRANCH=$(get_conf ".apps.und.upgrade.branch")
NUM_VALIDATORS=$(get_conf ".apps.und.nodes.num_validators")
NUM_SENTRIES=$(get_conf ".apps.und.nodes.num_sentries")
NUM_SEEDS=$(get_conf ".apps.und.nodes.num_seeds")
NUM_RPCS=$(get_conf ".apps.und.nodes.num_rpcs")
MIN_STAKE=$(get_conf ".apps.und.staking.min_stake")
MAX_STAKE=$(get_conf ".apps.und.staking.max_stake")
SMALL_MIN_STAKE=$(get_conf ".apps.und.staking.small_min_stake")
SMALL_MAX_STAKE=$(get_conf ".apps.und.staking.small_max_stake")
ACC_START_NUND=$(get_conf ".apps.und.staking.acc_start_nund")
ACCOUNT_START_NUND=$(get_conf ".apps.und.accounts.nund")
NUM_ENT_SIGNERS=$(get_conf ".apps.und.accounts.num_ent_signers")
NUM_ENT_ACCEPTS=$(get_conf ".apps.und.accounts.num_ent_accepts")
NUM_WRKCHAINS=$(get_conf ".apps.und.accounts.num_wrhchains")
NUM_BEACONS=$(get_conf ".apps.und.accounts.num_beacons")
NUM_TEST_ACCS=$(get_conf ".apps.und.accounts.num_tests")
STORAGE_PURCHASE=$(get_conf ".apps.und.accounts.storage_purchase")
ENT_PO_AMOUNT=$(get_conf ".apps.und.accounts.ent_po_amount")
GENESIS_TIME=$(get_conf ".apps.und.genesis_time")

# IBC
IBC_CHAIN_ID=$(get_conf ".apps.ibc.chain_id")
IBC_VER=$(get_conf ".apps.ibc.version")
HERMES_VER=$(get_conf ".apps.ibc.hermes_version")
NUM_IBC_ACCOUNTS=$(get_conf ".apps.ibc.accounts.num_ibc_accounts")

# Cosmovisor
COSMOVISOR_VER=$(get_conf ".apps.cosmovisor.version")

# Docker
SUBNET=$(get_conf ".docker.network.subnet")
IP_START=$(get_conf ".docker.network.ip_start")
P2P_PORT_START=$(get_conf ".docker.network.p2p_port_start")
RPC_PORT_START=$(get_conf ".docker.network.rpc_port_start")
REST_PORT_START=$(get_conf ".docker.network.rest_port_start")
GRPC_PORT_START=$(get_conf ".docker.network.grpc_port_start")
IBC_NODE_P2P_PORT=$(get_conf ".docker.network.ibc_node.p2p")
IBC_NODE_RPC_PORT=$(get_conf ".docker.network.ibc_node.rpc")
IBC_NODE_REST_PORT=$(get_conf ".docker.network.ibc_node.rest")
IBC_NODE_GRPC_PORT=$(get_conf ".docker.network.ibc_node.grpc")
CONTAINER_PREFIX=$(get_conf ".docker.container_prefix")
DOCKER_NETWORK="${CONTAINER_PREFIX}up_sim_network"

# Binaries required to generate genesis/accounts etc.
UND_BIN="${BIN_DIR}/und_${UND_GENESIS_VER}"
IBC_SIMD_BIN="${BIN_DIR}/ibc-go_simd_${IBC_VER}"
V_PREFIX="v"

# und releases prior to v1.6.1 were not tagged with the "v" prefix
if version_lt "${UND_GENESIS_VER}" "1.6.1"; then
  V_PREFIX=""
fi

# download_genesis_bin
# Checks if the required binary exists in third_party/bin.
# These are used for the initial generation of wallets, configs and genesis etc.
function download_genesis_bin() {
  local BIN_T=${1}
  local BIN=${2}
  local DL_LOC
  local TAR

  if [ $BIN_T = "und" ]; then
    DL_LOC="https://github.com/unification-com/mainchain/releases/download/${V_PREFIX}${UND_GENESIS_VER}/und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz"
    TAR="und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz"
  else
    DL_LOC="https://github.com/cosmos/ibc-go/releases/download/v${IBC_VER}/ibc-go_simd_v${IBC_VER}_linux_amd64.tar.gz"
    TAR="ibc-go_simd_v${IBC_VER}_linux_amd64.tar.gz"
  fi

  if ! test -f "$BIN"; then
    echo "Genesis binary for ${BIN_T} not found. Downloading"
    mkdir -p "${BIN_DIR}"/tmp
    cd "${BIN_DIR}"/tmp || exit
    wget "${DL_LOC}"
    tar -zxvf "${TAR}"
    mv "${BIN_T}" "${BIN}"
    rm -rf "${BIN_DIR}"/tmp
  fi
}

if [ ! -d "${THIRD_PARTY_DIR}" ]; then
  mkdir -p "${THIRD_PARTY_DIR}"
  cat >"${THIRD_PARTY_DIR}"/README.md <<EOL
# Third party binaries

The \`bin\` directory contains automatically downloaded binaries
required by the \`generate.sh\` script.
EOL
fi

# Check binaries required for generating exist
download_genesis_bin "und" "${UND_BIN}"
download_genesis_bin "simd" "${IBC_SIMD_BIN}"

cd "${BASE_DIR}" || exit

###########
# Variables
###########

# for beacons/wrkchains script
POP_B_WC_ACCS=""
POP_B_WC_TYPES=""
POP_B_WC_ACC_SEQUENCESS=""
POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS=""
POP_B_WC_HAS_PURCHASED_STORAGE=""
POP_B_WC_ENT_ACCS=""
POP_B_WC_ENT_ACC_SEQUENCESS=""

# for populate txs script
POP_TXS_NODE_ACCS=""
POP_TXS_TEST_ACCS=""
POP_TXS_IBC_ACCS_FUND=""
POP_TXS_IBC_ACCS_SIMD=""
POP_TXS_NODE_ACC_SEQUENCESS=""
POP_TXS_USER_ACC_SEQUENCESS=""
POP_TXS_IBC_ACC_SEQUENCESS_FUND=""
POP_TXS_IBC_ACC_SEQUENCESS_SIMD=""

################
# Main Functions
################

function _jq() {
   echo "${1}" | base64 --decode | jq -r "${2}"
}

function add_account_to_genesis() {
  local ADDR=$1
  local AMT=$2

  ${UND_BIN} add-genesis-account "${ADDR}" "${AMT}nund" --home="${GLOBAL_TMP_UND_HOME}"
}

function generate_account_and_add_to_genesis() {
  local ACC_NAME=$1
  local AMNT=$2
  local IMPORT_RES
  local WALLET_ADDRESS

  IMPORT_RES=$(${UND_BIN} keys add "${ACC_NAME}" --keyring-backend=test --home="${ASSET_KEYS_DIR_UND}" --output=json 2>&1)

  WALLET_ADDRESS=$(echo "${IMPORT_RES}" | jq -r ".address")

  add_account_to_genesis "${WALLET_ADDRESS}" "${AMNT}"

  echo "${WALLET_ADDRESS}"
}

function init_ibc_simd() {
  local IBC_TMP_DIR="${TMP_DIR}/ibc_net/node"
  local IBC_WALLERS_DIR="${TMP_DIR}/ibc_net/wallets"
  local IBC_WALLET_CONF="${IBC_WALLERS_DIR}/simd_validator.json"
  local IMPORT_RES
  local VALIDATOR_WALLET_ADDRESS
  local VALIDATOR_MNEMONIC
  local SIMD_ACC_NAME="simd_validator"

  mkdir -p "${IBC_WALLERS_DIR}"

  ${IBC_SIMD_BIN} init devnet-validator --chain-id="${IBC_CHAIN_ID}" --home "${IBC_TMP_DIR}"
  ${IBC_SIMD_BIN} config chain-id "${IBC_CHAIN_ID}" --home "${IBC_TMP_DIR}"
  ${IBC_SIMD_BIN} config keyring-backend test --home "${IBC_TMP_DIR}"
  ${IBC_SIMD_BIN} config node "tcp://localhost:${IBC_NODE_RPC_PORT}" --home "${IBC_TMP_DIR}"

  IMPORT_RES=$(${IBC_SIMD_BIN} keys add "${SIMD_ACC_NAME}" --keyring-backend=test --home="${IBC_TMP_DIR}" --output=json 2>&1)
  VALIDATOR_WALLET_ADDRESS=$(echo "${IMPORT_RES}" | jq -r ".address")
  VALIDATOR_MNEMONIC=$(echo "${IMPORT_RES}" | jq -r ".mnemonic")

  ${IBC_SIMD_BIN} add-genesis-account ${SIMD_ACC_NAME} 100000000000000stake --home "${IBC_TMP_DIR}" --keyring-backend test
  ${IBC_SIMD_BIN} gentx ${SIMD_ACC_NAME} 1000000stake --home "${IBC_TMP_DIR}" --chain-id="${IBC_CHAIN_ID}"
  ${IBC_SIMD_BIN} collect-gentxs --home "${IBC_TMP_DIR}"

  sed -i "s/enable = false/enable = true/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/swagger = false/swagger = true/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/address = \"tcp:\/\/0.0.0.0:1317\"/address = \"tcp:\/\/0.0.0.0:${IBC_NODE_REST_PORT}\"/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/address = \"0.0.0.0:9090\"/address = \"0.0.0.0:${IBC_NODE_GRPC_PORT}\"/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/address = \"0.0.0.0:9091\"/address = \"0.0.0.0:9999\"/g" "${IBC_TMP_DIR}/config/app.toml" && \
  sed -i "s/laddr = \"tcp:\/\/127.0.0.1:26657\"/laddr = \"tcp:\/\/0.0.0.0:${IBC_NODE_RPC_PORT}\"/g" "${IBC_TMP_DIR}/config/config.toml" && \
  sed -i "s/laddr = \"tcp:\/\/0.0.0.0:26656\"/laddr = \"tcp:\/\/0.0.0.0:${IBC_NODE_P2P_PORT}\"/g" "${IBC_TMP_DIR}/config/config.toml" && \
  sed -i "s/cors_allowed_origins = \[\]/ cors_allowed_origins = \[\"*\"\]/g" "${IBC_TMP_DIR}/config/config.toml" && \

  cat >"${IBC_WALLET_CONF}" <<EOL
{
  "mnemonic": "${VALIDATOR_MNEMONIC}",
  "simd_address": "${VALIDATOR_WALLET_ADDRESS}",
  "amount": "100000000000000"
}
EOL
}

function generate_ibc_test_account() {
  local ACC_IDX=${1}
  local ACC_PREFIX=${2}
  local AMNT=${3}
  local UND_ACC_NAME="${ACC_PREFIX}_und${ACC_IDX}"
  local SIMD_ACC_NAME="${ACC_PREFIX}_simd${ACC_IDX}"
  local IMPORT_RES
  local UND_WALLET_ADDRESS
  local SIMD_WALLET_ADDRESS
  local IBC_MNEMONIC
  local IBC_TMP_DIR="${TMP_DIR}/ibc_net/wallets"
  local IBC_WALLET_CONF="${IBC_TMP_DIR}/${ACC_PREFIX}${ACC_IDX}.json"
  local IBC_NODE_DIR="${TMP_DIR}/ibc_net/node"

  mkdir -p "${IBC_TMP_DIR}"

  # und
  IMPORT_RES=$(${UND_BIN} keys add "${UND_ACC_NAME}" --keyring-backend=test --home="${ASSET_KEYS_DIR_UND}" --output=json 2>&1)
  IBC_MNEMONIC=$(echo "${IMPORT_RES}" | jq -r ".mnemonic")
  UND_WALLET_ADDRESS=$(echo "${IMPORT_RES}" | jq -r ".address")
  add_account_to_genesis "${UND_WALLET_ADDRESS}" "${AMNT}"

  # simd
  IMPORT_RES=$(yes "${IBC_MNEMONIC}" | ${IBC_SIMD_BIN} keys add "${SIMD_ACC_NAME}" --recover  --keyring-backend=test --home="${IBC_NODE_DIR}" --output=json 2>&1)
  SIMD_WALLET_ADDRESS=$(echo "${IMPORT_RES}" | jq -r ".address")

  ${IBC_SIMD_BIN} add-genesis-account "${SIMD_ACC_NAME}" 100000000000000stake --home "${IBC_NODE_DIR}" --keyring-backend test

  cat >"${IBC_WALLET_CONF}" <<EOL
{
  "mnemonic": "${IBC_MNEMONIC}",
  "und_address": "${UND_WALLET_ADDRESS}",
  "simd_address": "${SIMD_WALLET_ADDRESS}",
  "amount": "${AMNT}"
}
EOL

}

function config_hermes() {
  local HERMES_ASSETS="${ASSETS_DIR}/ibc_net/hermes"
  local FUND_RPC=${1}
  local FUND_GRPC=${2}
  local SIMD_RPC=${3}
  local SIMD_GRPC=${4}

  mkdir -p "${HERMES_ASSETS}"

  cp "${BASE_TEMPLATES_DIR}"/configs/hermes_config.toml "${HERMES_ASSETS}"/config.toml

  sed -i "s/__FUND_RPC__/${FUND_RPC}/g" "${HERMES_ASSETS}"/config.toml
  sed -i "s/__FUND_GRPC__/${FUND_GRPC}/g" "${HERMES_ASSETS}"/config.toml
  sed -i "s/__IBC_SIMD_RPC__/${SIMD_RPC}/g" "${HERMES_ASSETS}"/config.toml
  sed -i "s/__IBC_SIMD_GRPC__/${SIMD_GRPC}/g" "${HERMES_ASSETS}"/config.toml
  sed -i "s/__FUND_CHAIN_ID__/${CHAIN_ID}/g" "${HERMES_ASSETS}"/config.toml
  sed -i "s/__IBC_CHAIN_ID__/${IBC_CHAIN_ID}/g" "${HERMES_ASSETS}"/config.toml
}

function generate_node() {
  local NODE_TYPE=$1
  local NODE_PREFIX=$2
  local NODE_NUM=$3

  local NODE_NAME="${NODE_PREFIX}${NODE_NUM}"
  local NODE_IP="${SUBNET}.${IP_START}"
  local NODE_TMP_DIR="${TMP_DIR}/$NODE_NAME"
  local NODE_CONF="${NODE_TMP_DIR}/node_conf.json"
  local WALLET_CONF="${NODE_TMP_DIR}/wallet_conf.json"
  local GENTX_CONF="${NODE_TMP_DIR}/gentx_conf.json"
  local NODE_P2P_PORT=${P2P_PORT_START}
  local NODE_P2P="${NODE_IP}:${NODE_P2P_PORT}"

  local NODE_TMP_UND_HOME="${NODE_TMP_DIR}/.und_mainchain"

  local TENDERMINT_NODE_ID
  local NODE_P2P_ADDR

  mkdir -p "${NODE_TMP_DIR}"

  echo "${NODE_NAME} = ${NODE_P2P}"

  "${UND_BIN}" init "${NODE_NAME}" --home "${NODE_TMP_UND_HOME}"
  TENDERMINT_NODE_ID=$(${UND_BIN} tendermint show-node-id --home="${NODE_TMP_UND_HOME}" 2>&1)
  NODE_P2P_ADDR="${TENDERMINT_NODE_ID}@${NODE_P2P}"

  cat >"${NODE_CONF}" <<EOL
{
  "name":"${NODE_NAME}",
  "type":"${NODE_TYPE}",
  "ip":"${NODE_IP}",
  "p2p_port":"${NODE_P2P_PORT}",
  "p2p_addr":"${NODE_P2P_ADDR}",
  "tm_node_id":"${TENDERMINT_NODE_ID}",
  "rpc_port":"${RPC_PORT_START}",
  "rest_port":"${REST_PORT_START}",
  "grpc_port":"${GRPC_PORT_START}"
}
EOL

  if [ "$NODE_TYPE" = "val" ]; then
    local IMPORT_RES
    local WALLET_NAME
    local WALLET_MNEMONIC
    local WALLET_ADDRESS
    local WALLET_PUB_KEY
    local TENDERMINT_VAL_INFO
    local COMMISSION_RATE="0.1"
    local COMMISSION_MAX_RATE="0.1"
    local COMMISSION_MAX_CHANGE_RATE="0.01"

    # ToDo: Make these configurable
    # set node1
    # COMMISSION_RATE = 0%
    # COMMISSION_MAX_RATE = 1%
    # COMMISSION_MAX_CHANGE_RATE = 1%
    if [ "$NODE_NUM" = "1" ]; then
      COMMISSION_RATE="0"
      COMMISSION_MAX_RATE="0.1"
      COMMISSION_MAX_CHANGE_RATE="0.01"
    fi

    # set node2
    # COMMISSION_RATE = 3%
    # COMMISSION_MAX_RATE to 3%
    # COMMISSION_MAX_CHANGE_RATE = 1%
    if [ "$NODE_NUM" = "2" ]; then
      COMMISSION_RATE="0.03"
      COMMISSION_MAX_RATE="0.04"
      COMMISSION_MAX_CHANGE_RATE="0.01"
    fi

    # set node3
    # COMMISSION_RATE = 3%
    # COMMISSION_MAX_RATE to 10%
    # COMMISSION_MAX_CHANGE_RATE = 1%
    if [ "$NODE_NUM" = "3" ]; then
      COMMISSION_RATE="0.03"
      COMMISSION_MAX_RATE="0.1"
      COMMISSION_MAX_CHANGE_RATE="0.01"
    fi

    # set node4
    # COMMISSION_RATE = 3%
    # COMMISSION_MAX_RATE to 10%
    # COMMISSION_MAX_CHANGE_RATE = 5%
    if [ "$NODE_NUM" = "4" ]; then
      COMMISSION_RATE="0.03"
      COMMISSION_MAX_RATE="0.1"
      COMMISSION_MAX_CHANGE_RATE="0.05"
    fi

    IMPORT_RES=$(${UND_BIN} keys add "${NODE_NAME}" --keyring-backend=test --keyring-dir="${NODE_TMP_UND_HOME}" --output=json 2>&1)

    WALLET_NAME=$(echo "${IMPORT_RES}" | jq -r ".name")
    WALLET_MNEMONIC=$(echo "${IMPORT_RES}" | jq -r ".mnemonic")
    WALLET_ADDRESS=$(echo "${IMPORT_RES}" | jq -r ".address")
    WALLET_PUB_KEY=$(echo "${IMPORT_RES}" | jq -r ".pubkey")

    TENDERMINT_VAL_INFO=$(${UND_BIN} tendermint show-validator --home="${NODE_TMP_UND_HOME}" 2>&1)

    add_account_to_genesis "${WALLET_ADDRESS}" "${ACC_START_NUND}"

    local IS_SMALL
    IS_SMALL=$(awk "BEGIN {print $NODE_NUM%5}")
    if [ "$IS_SMALL" = "0" ]; then
      NODE_STAKE=$(awk "BEGIN{srand();print int(rand()*($SMALL_MAX_STAKE-$SMALL_MIN_STAKE))+$SMALL_MIN_STAKE }")
      echo "${NODE_NAME} Small Stake = ${NODE_STAKE}"
    else
      NODE_STAKE=$(awk "BEGIN{srand();print int(rand()*($MAX_STAKE-$MIN_STAKE))+$MIN_STAKE }")
      echo "${NODE_NAME} Large Stake = ${NODE_STAKE}"
    fi

    cp "${NODE_TMP_UND_HOME}"/keyring-test/* "${ASSET_KEYS_DIR_UND}"/

    ESCAPED_PUB_KEY=$(echo "${WALLET_PUB_KEY}" | sed 's/"/\\"/g')
    ESCAPED_TENDERMINT_VAL_INFO=$(echo "${TENDERMINT_VAL_INFO}" | sed 's/"/\\"/g')

    cat >"${WALLET_CONF}" <<EOL
{
  "name": "${WALLET_NAME}",
  "mnemonic": "${WALLET_MNEMONIC}",
  "address": "${WALLET_ADDRESS}",
  "pub_key": "${ESCAPED_PUB_KEY}"
}
EOL

    cat >"${GENTX_CONF}" <<EOL
{
  "stake": "${NODE_STAKE}nund",
  "commission_rate": "${COMMISSION_RATE}",
  "commission_max_rate": "${COMMISSION_MAX_RATE}",
  "commission_max_change_rate": "${COMMISSION_MAX_CHANGE_RATE}",
  "min_self_delegation": "1",
  "pub_key": "${ESCAPED_TENDERMINT_VAL_INFO}"
}
EOL
  fi

  sed -i "s/minimum-gas-prices = \"\"/minimum-gas-prices = \"25.0nund\"/g" "${NODE_TMP_UND_HOME}/config/app.toml"
  sed -i "s/addr_book_strict = true/addr_book_strict = false/g" "${NODE_TMP_UND_HOME}/config/config.toml"

  sed -i "s/snapshot-interval = 0/snapshot-interval = 100/g" "${NODE_TMP_UND_HOME}/config/app.toml"
  sed -i "s/snapshot-keep-recent = 2/snapshot-keep-recent = 5/g" "${NODE_TMP_UND_HOME}/config/app.toml"

  if [ "$NODE_TYPE" = "val" ]; then
    sed -i "s/indexer = \"kv\"/indexer = \"null\"/g" "${NODE_TMP_UND_HOME}/config/config.toml"
  fi

  IP_START=$(awk "BEGIN {print $IP_START+1}")
  P2P_PORT_START=$(awk "BEGIN {print $P2P_PORT_START+1}")
  RPC_PORT_START=$(awk "BEGIN {print $RPC_PORT_START+1}")
  GRPC_PORT_START=$(awk "BEGIN {print $GRPC_PORT_START+1}")
  local REST_PORT=${REST_PORT_START}
  REST_PORT_START=$(awk "BEGIN {print $REST_PORT_START+1}")

  if [ "$NODE_TYPE" = "rpc" ]; then
    sed -i "s/pruning = \"default\"/pruning = \"nothing\"/g" "${NODE_TMP_UND_HOME}/config/app.toml"
    sed -i "s/enable = false/enable = true/g" "${NODE_TMP_UND_HOME}/config/app.toml"
    sed -i "s/swagger = false/swagger = true/g" "${NODE_TMP_UND_HOME}/config/app.toml"
    sed -i "s/address = \"tcp:\/\/0.0.0.0:1317\"/address = \"tcp:\/\/0.0.0.0:$REST_PORT\"/g" "${NODE_TMP_UND_HOME}/config/app.toml"
  fi

  echo "${NODE_NAME}" >> "${GENERATED_NETWORK}"
}

function generate_gentx() {
  local NODE_PREFIX=$1
  local NODE_NUM=$2

  local NODE_NAME="${NODE_PREFIX}${NODE_NUM}"
  local NODE_TMP_DIR="${TMP_DIR}/$NODE_NAME"
  local NODE_TMP_UND_HOME="${NODE_TMP_DIR}/.und_mainchain"
  local NODE_CONF="${NODE_TMP_DIR}/node_conf.json"
  local WALLET_CONF="${NODE_TMP_DIR}/wallet_conf.json"
  local GENTX_CONF="${NODE_TMP_DIR}/gentx_conf.json"

  local STAKE
  local COMMISSION
  local COMMISSION_MAX
  local COMMISSION_MAX_CHANGE
  local MIN_SELF_DEL
  local PUB_KEY
  local IP
  local NODE_ID

  STAKE=$(cat < "${GENTX_CONF}" | jq -r ".stake")
  COMMISSION=$(cat < "${GENTX_CONF}" | jq -r ".commission_rate")
  COMMISSION_MAX=$(cat < "${GENTX_CONF}" | jq -r ".commission_max_rate")
  COMMISSION_MAX_CHANGE=$(cat < "${GENTX_CONF}" | jq -r ".commission_max_change_rate")
  MIN_SELF_DEL=$(cat < "${GENTX_CONF}" | jq -r ".min_self_delegation")
  PUB_KEY=$(cat < "${GENTX_CONF}" | jq -r ".pub_key")

  IP=$(cat < "${NODE_CONF}" | jq -r ".ip")
  NODE_ID=$(cat < "${NODE_CONF}" | jq -r ".tm_node_id")

  cp "${GLOBAL_TMP_UND_HOME}"/config/genesis.json "${NODE_TMP_UND_HOME}/config/genesis.json"

  echo "gentx for ${NODE_NAME}"

  ${UND_BIN} gentx "${NODE_NAME}" "${STAKE}" \
                   --home "${NODE_TMP_UND_HOME}" \
                   --commission-rate "${COMMISSION}" \
                   --commission-max-rate "${COMMISSION_MAX}" \
                   --commission-max-change-rate "${COMMISSION_MAX_CHANGE}" \
                   --min-self-delegation "${MIN_SELF_DEL}" \
                   --moniker "${NODE_NAME}" \
                   --keyring-backend test \
                   --details "${NODE_NAME}" \
                   --ip "${IP}" \
                   --pubkey "${PUB_KEY}" \
                   --node-id "${NODE_ID}" \
                   --chain-id "${CHAIN_ID}" \
                   --from "${NODE_NAME}" \
                   --output-document "${TX_DIR}/${NODE_NAME}.json"

}

function collect_genxs() {
  local NODE_PREFIX=$1
  local NODE_NUM=$2

  local NODE_NAME="${NODE_PREFIX}${NODE_NUM}"
  local NODE_TMP_DIR="${TMP_DIR}/$NODE_NAME"
  local NODE_TMP_UND_HOME="${NODE_TMP_DIR}/.und_mainchain"

  cp "${GLOBAL_TMP_UND_HOME}"/config/genesis.json "${NODE_TMP_UND_HOME}/config/genesis.json"

  local GENTX_DIR="${NODE_TMP_UND_HOME}/config/gentx"
  if [ -d "$GENTX_DIR" ]; then
    rm -rf "${GENTX_DIR}"
  fi
  mkdir -p "${GENTX_DIR}"

  cp "${TX_DIR}/"* "${GENTX_DIR}"

  ${UND_BIN} collect-gentxs --home="${NODE_TMP_UND_HOME}"

}

function configure_node_assets() {
  local NODE_NAME=$1
  local NODE_TMP_DIR="${TMP_DIR}/$NODE_NAME"
  local NODE_CONF="${NODE_TMP_DIR}/node_conf.json"
  local NODE_UND_CONF_TOML="${NODE_TMP_DIR}/.und_mainchain/config/config.toml"
  local NODE_UND_APP_TOML="${NODE_TMP_DIR}/.und_mainchain/config/app.toml"

  local NODE_TYPE
  local NODE_IP
  local P2P_PORT
  local RPC_PORT
  local REST_PORT
  local GRPC_PORT
  local SEED_NODES=""
  local PRIVATE_NODE_IDS=""
  local PERSISTENT_PEERS=""
  local PERSISTENT_PEERS_FOR_SEED=""

  NODE_TYPE=$(cat < "${NODE_CONF}" | jq -r ".type")
  NODE_IP=$(cat < "${NODE_CONF}" | jq -r ".ip")
  P2P_PORT=$(cat < "${NODE_CONF}" | jq -r ".p2p_port")
  RPC_PORT=$(cat < "${NODE_CONF}" | jq -r ".rpc_port")
  REST_PORT=$(cat < "${NODE_CONF}" | jq -r ".rest_port")
  GRPC_PORT=$(cat < "${NODE_CONF}" | jq -r ".grpc_port")

  while read -r p; do
    if [ "$p" != "$NODE_NAME" ]; then
      local NT
      local NN
      local N_P2P_ADDR
      local NODE_ID
      local N_IP

      local NC="${TMP_DIR}/${p}/node_conf.json"
      NT=$(cat < "${NC}" | jq -r ".type")
      NN=$(cat < "${NC}" | jq -r ".name")
      N_P2P_ADDR=$(cat < "${NC}" | jq -r ".p2p_addr")
      NODE_ID=$(cat < "${NC}" | jq -r ".tm_node_id")
      N_IP=$(cat < "${NC}" | jq -r ".ip")
      local P2P_TO_CHANGE="${NODE_ID}@${N_IP}:26656"

      sed -i "s/$P2P_TO_CHANGE/$N_P2P_ADDR/g" "${NODE_UND_CONF_TOML}"

      if [ "$NT" = "seed" ]; then
        SEED_NODES+="${N_P2P_ADDR},"
      fi
      if [ "$NT" = "val" ]; then
        PRIVATE_NODE_IDS+="${NODE_ID},"
      fi
      if [ "$NT" = "val" ] || [ "$NT" = "sentry" ]; then
        if [ "$NN" != "$NODE_NAME" ]; then
          PERSISTENT_PEERS+="${N_P2P_ADDR},"
        fi
      fi
      if [ "$NT" = "sentry" ]; then
        PERSISTENT_PEERS_FOR_SEED+="${N_P2P_ADDR},"
      fi
    fi
  done <"${GENERATED_NETWORK}"

  SEED_NODES=$(echo "${SEED_NODES}" | sed 's/\(.*\),/\1/')
  PRIVATE_NODE_IDS=$(echo "${PRIVATE_NODE_IDS}" | sed 's/\(.*\),/\1/')
  PERSISTENT_PEERS=$(echo "${PERSISTENT_PEERS}" | sed 's/\(.*\),/\1/')
  PERSISTENT_PEERS_FOR_SEED=$(echo "${PERSISTENT_PEERS_FOR_SEED}" | sed 's/\(.*\),/\1/')

  if [ "$NODE_TYPE" = "sentry" ] || [ "$NODE_TYPE" = "rpc" ]; then
    sed -i "s/seeds = \"\"/seeds = \"$SEED_NODES\"/g" "${NODE_UND_CONF_TOML}"
    sed -i "s/private_peer_ids = \"\"/private_peer_ids = \"$PRIVATE_NODE_IDS\"/g" "${NODE_UND_CONF_TOML}"
  fi

  if [ "$NODE_TYPE" = "sentry" ] || [ "$NODE_TYPE" = "val" ]; then
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PERSISTENT_PEERS\"/g" "${NODE_UND_CONF_TOML}"
  fi

  if [ "$NODE_TYPE" = "val" ]; then
    sed -i "s/pex = true/pex = false/g" "${NODE_UND_CONF_TOML}"
  fi

  if [ "$NODE_TYPE" = "seed" ]; then
    sed -i "s/seed_mode = false/seed_mode = true/g" "${NODE_UND_CONF_TOML}"
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PERSISTENT_PEERS_FOR_SEED\"/g" "${NODE_UND_CONF_TOML}"
  fi

  if [ "$NODE_TYPE" = "rpc" ]; then
    sed -i "s/laddr = \"tcp:\/\/127.0.0.1:26657\"/laddr = \"tcp:\/\/0.0.0.0:$RPC_PORT\"/g" "${NODE_UND_CONF_TOML}"
  fi

  sed -i "s/address = \"0.0.0.0:9090\"/address = \"0.0.0.0:$GRPC_PORT\"/g" "${NODE_UND_APP_TOML}"

  sed -i "s/laddr = \"tcp:\/\/0.0.0.0:26656\"/laddr = \"tcp:\/\/0.0.0.0:$P2P_PORT\"/g" "${NODE_UND_CONF_TOML}"

  cp -r "${NODE_TMP_DIR}" "${NODE_ASSETS_DIR}"/

  cat >>"${DOCKER_COMPOSE}" <<EOL
  ${CONTAINER_PREFIX}fund_${NODE_NAME}:
    hostname: ${CONTAINER_PREFIX}fund_${NODE_NAME}
    build:
      context: .
      dockerfile: docker/und.Dockerfile
      args:
        NODE_NAME: "${NODE_NAME}"
        UPGRADE_PLAN_NAME: "${UPGRADE_PLAN_NAME}"
        UND_GENESIS_VER: "${UND_GENESIS_VER}"
        IBC_VER: "${IBC_VER}"
        UND_UPGRADE_BRANCH: "${UND_UPGRADE_BRANCH}"
        V_PREFIX: "${V_PREFIX}"
        COSMOVISOR_VER: "${COSMOVISOR_VER}"
    container_name: ${CONTAINER_PREFIX}fund_${NODE_NAME}
    command:  >
      /bin/bash -c "
        cd /root &&
        ./run_node.sh
      "
    networks:
      ${DOCKER_NETWORK}:
        ipv4_address: ${NODE_IP}
    ports:
      - "${P2P_PORT}:${P2P_PORT}"
      - "${RPC_PORT}:${RPC_PORT}"
      - "${REST_PORT}:${REST_PORT}"
      - "${GRPC_PORT}:${GRPC_PORT}"
    volumes:
      - ./out/$NODE_NAME:/root/out:rw

EOL
}

##########################
# BEGIN GENERATING PROCESS
##########################

# create directories

# Check for and remove tmp
if [ -d "$TMP_DIR" ]; then
  rm -rf "${TMP_DIR}"
fi

# Check for and remove generated/assets
if [ -d "$ASSETS_DIR" ]; then
  rm -rf "${ASSETS_DIR}"
fi

# Check for and remove out
if [ -d "$DOCKER_OUT_DIR" ]; then
  rm -rf "${DOCKER_OUT_DIR:?}"/*
fi

mkdir -p "${NODE_ASSETS_DIR}"
mkdir -p "${ASSET_KEYS_DIR_UND}"
mkdir -p "${ASSET_KEYS_DIR_SIMD}"
mkdir -p "${ASSETS_SCRIPTS_DIR}"
mkdir -p "${ASSETS_TXS_DIR}"

mkdir -p "${GLOBAL_TMP_HOME}"

mkdir -p "${TX_DIR}"

# initialise genesis.json using correct und version
${UND_BIN} init global --home "${GLOBAL_TMP_UND_HOME}" --chain-id "${CHAIN_ID}"

# Modify for nund etc.
sed -i "s/stake/nund/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"voting_period\": \"172800s\"/\"voting_period\": \"90s\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"max_deposit_period\": \"172800s\"/\"max_deposit_period\": \"90s\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"fee_purchase_storage\": \"5000000000\"/\"fee_purchase_storage\": \"1000000000\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"default_storage_limit\": \"50000\"/\"default_storage_limit\": \"100\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"max_storage_limit\": \"600000\"/\"max_storage_limit\": \"200\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"

if [ "$GENESIS_TIME" != "null" ]; then
  sed -i "s/\"genesis_time\": \".*\"/\"genesis_time\": \"${GENESIS_TIME}\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
fi

# initialise docker-compose.yml
cat >"${DOCKER_COMPOSE}" <<EOL
version: "3"
services:
EOL

# copy scripts to docker assets
cp "${BASE_SCRIPTS_DIR}"/* "${ASSETS_SCRIPTS_DIR}"

#################
# base accounts
#################

ENT_ADDRESSES=""
for (( i=1; i<=NUM_ENT_SIGNERS; i++ ))
do
  ENT_ACC_NAME="ent${i}"
  ENT_ADDR=$(generate_account_and_add_to_genesis "${ENT_ACC_NAME}" "${ACCOUNT_START_NUND}")
  ENT_ADDRESSES+="${ENT_ADDR},"
  POP_B_WC_ENT_ACCS+="\"${ENT_ACC_NAME}\" "
  POP_B_WC_ENT_ACC_SEQUENCESS+="0 "
done

ENT_ADDRESSES=$(echo "${ENT_ADDRESSES}" | sed 's/\(.*\),/\1/')
sed -i "s/\"min_accepts\": \"1\"/\"min_accepts\": \"${NUM_ENT_ACCEPTS}\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"
sed -i "s/\"ent_signers\": \"und1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq5x8kpm\"/\"ent_signers\": \"$ENT_ADDRESSES\"/g" "${GLOBAL_TMP_UND_HOME}/config/genesis.json"

for (( i=1; i<=NUM_WRKCHAINS; i++ ))
do
  WC_ACC_NAME="wc${i}"
  generate_account_and_add_to_genesis "${WC_ACC_NAME}" "${ACCOUNT_START_NUND}"
  POP_B_WC_ACCS+="\"${WC_ACC_NAME}\" "
  POP_B_WC_TYPES+="\"wrkchain\" "
  POP_B_WC_ACC_SEQUENCESS+="0 "
  POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS+="1 "
  POP_B_WC_HAS_PURCHASED_STORAGE+="0 "
done

for (( i=1; i<=NUM_BEACONS; i++ ))
do
  BEACON_ACC_NAME="b${i}"
  generate_account_and_add_to_genesis "${BEACON_ACC_NAME}" "${ACCOUNT_START_NUND}"
  POP_B_WC_ACCS+="\"${BEACON_ACC_NAME}\" "
  POP_B_WC_TYPES+="\"beacon\" "
  POP_B_WC_ACC_SEQUENCESS+="0 "
  POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS+="1 "
  POP_B_WC_HAS_PURCHASED_STORAGE+="0 "
done

sed -i "s/__POP_B_WC_ACCS__/$POP_B_WC_ACCS/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_TYPES__/$POP_B_WC_TYPES/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_ACC_SEQUENCESS__/$POP_B_WC_ACC_SEQUENCESS/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS__/$POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_HAS_PURCHASED_STORAGE__/$POP_B_WC_HAS_PURCHASED_STORAGE/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_ENT_ACCS__/$POP_B_WC_ENT_ACCS/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__POP_B_WC_ENT_ACC_SEQUENCESS__/$POP_B_WC_ENT_ACC_SEQUENCESS/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh
sed -i "s/__ENT_PO_AMOUNT__/$ENT_PO_AMOUNT/g" "${ASSETS_SCRIPTS_DIR}"/populate_beacons_wrkchains.sh

for (( i=1; i<=NUM_TEST_ACCS; i++ ))
do
  TEST_ACC_NAME="t${i}"
  generate_account_and_add_to_genesis "${TEST_ACC_NAME}" "${ACCOUNT_START_NUND}"
  POP_TXS_TEST_ACCS+="\"${TEST_ACC_NAME}\" "
  POP_TXS_USER_ACC_SEQUENCESS+="0 "
done

sed -i "s/__POP_TXS_TEST_ACCS__/$POP_TXS_TEST_ACCS/g" "${ASSETS_SCRIPTS_DIR}"/populate_txs.sh
sed -i "s/__POP_TXS_USER_ACC_SEQUENCESS__/$POP_TXS_USER_ACC_SEQUENCESS/g" "${ASSETS_SCRIPTS_DIR}"/populate_txs.sh

# Init IBC Simd
init_ibc_simd

# IBC Test accounts
for (( i=1; i<=NUM_IBC_ACCOUNTS; i++ ))
do
  IBC_UND_ACC_NAME="ibc_und${i}"
  IBC_SIMD_ACC_NAME="ibc_simd${i}"
  generate_ibc_test_account "${i}" "ibc" "${ACCOUNT_START_NUND}"
  POP_TXS_IBC_ACCS_FUND+="\"${IBC_UND_ACC_NAME}\" "
  POP_TXS_IBC_ACC_SEQUENCESS_FUND+="0 "
  POP_TXS_IBC_ACCS_SIMD+="\"${IBC_SIMD_ACC_NAME}\" "
  POP_TXS_IBC_ACC_SEQUENCESS_SIMD+="0 "
done

sed -i "s/__POP_TXS_IBC_ACCS_FUND__/$POP_TXS_IBC_ACCS_FUND/g" "${ASSETS_SCRIPTS_DIR}"/populate_ibc.sh
sed -i "s/__POP_TXS_IBC_ACC_SEQUENCESS_FUND__/$POP_TXS_IBC_ACC_SEQUENCESS_FUND/g" "${ASSETS_SCRIPTS_DIR}"/populate_ibc.sh
sed -i "s/__POP_TXS_IBC_ACCS_SIMD__/$POP_TXS_IBC_ACCS_SIMD/g" "${ASSETS_SCRIPTS_DIR}"/populate_ibc.sh
sed -i "s/__POP_TXS_IBC_ACC_SEQUENCESS_SIMD__/$POP_TXS_IBC_ACC_SEQUENCESS_SIMD/g" "${ASSETS_SCRIPTS_DIR}"/populate_ibc.sh

# IBC RELAYER ACC
generate_ibc_test_account "1" "hermes" "${ACCOUNT_START_NUND}"

mv "${ASSET_KEYS_DIR_UND}"/keyring-test/* "${ASSET_KEYS_DIR_UND}"
cp "${TMP_DIR}"/ibc_net/node/keyring-test/* "${ASSET_KEYS_DIR_SIMD}"
rmdir "${ASSET_KEYS_DIR_UND}"/keyring-test/

cp -r "${TMP_DIR}"/ibc_net "${ASSETS_DIR}"/ibc_net/
rm -rf "${ASSET_KEYS_DIR_UND}"/config
rm -rf "${ASSET_KEYS_DIR_UND}"/data


#################
# Generate nodes
#################

# validators
for (( i=1; i<=NUM_VALIDATORS; i++ ))
do
  generate_node "val" "validator" "${i}"
  POP_TXS_NODE_ACCS+="\"validator${i}\" "
  POP_TXS_NODE_ACC_SEQUENCESS+="0 "
done

sed -i "s/__POP_TXS_NODE_ACCS__/$POP_TXS_NODE_ACCS/g" "${ASSETS_SCRIPTS_DIR}"/populate_txs.sh
sed -i "s/__POP_TXS_NODE_ACC_SEQUENCESS__/$POP_TXS_NODE_ACC_SEQUENCESS/g" "${ASSETS_SCRIPTS_DIR}"/populate_txs.sh

for (( i=1; i<=NUM_VALIDATORS; i++ ))
do
   generate_gentx "validator" "${i}"
done

# sentries
for (( i=1; i<=NUM_SENTRIES; i++ ))
do
   generate_node "sentry" "sentry" "${i}"
done

# seeds
for (( i=1; i<=NUM_SEEDS; i++ ))
do
   generate_node "seed" "seed" "${i}"
done

# rpcs
for (( i=1; i<=NUM_RPCS; i++ ))
do
   generate_node "rpc" "rpc" "${i}"
done

#################
# collect gentxs
#################
for (( i=1; i<=NUM_VALIDATORS; i++ ))
do
   collect_genxs "validator" "${i}"
done
for (( i=1; i<=NUM_SENTRIES; i++ ))
do
   collect_genxs "sentry" "${i}"
done
for (( i=1; i<=NUM_SEEDS; i++ ))
do
   collect_genxs "seed" "${i}"
done
for (( i=1; i<=NUM_RPCS; i++ ))
do
   collect_genxs "rpc" "${i}"
done

#############################
# build and configure network
#############################

while read -r p; do
  echo "configure $p"
  configure_node_assets "${p}"
done <"${GENERATED_NETWORK}"

# assume at least 1 rpc

RPC1_CONF="${TMP_DIR}/rpc1/node_conf.json"
RPC1_IP=$(cat < "${RPC1_CONF}" | jq -r ".ip")
RPC1_PORT=$(cat < "${RPC1_CONF}" | jq -r ".rpc_port")
RPC1_GRPC_PORT=$(cat < "${RPC1_CONF}" | jq -r ".grpc_port")
RPC1_REST_PORT=$(cat < "${RPC1_CONF}" | jq -r ".rest_port")

# Tx runner IP
IP_START=$(awk "BEGIN {print $IP_START+1}")
TX_RUNNER_IP="${SUBNET}.${IP_START}"

# Proxy IP (for wallet tests)
IP_START=$(awk "BEGIN {print $IP_START+1}")
PROXY_IP="${SUBNET}.${IP_START}"

# IBC SIMD IP
IP_START=$(awk "BEGIN {print $IP_START+1}")
IBC_SIMD_IP="${SUBNET}.${IP_START}"

# Hermes IP
IP_START=$(awk "BEGIN {print $IP_START+1}")
HERMES_IP="${SUBNET}.${IP_START}"

HERMES_FUND_RPC="${RPC1_IP}:${RPC1_PORT}"
HERMES_FUND_GRPC="${RPC1_IP}:${RPC1_GRPC_PORT}"
HERMES_SIMD_RPC="${IBC_SIMD_IP}:${IBC_NODE_RPC_PORT}"
HERMES_SIMD_GRPC="${IBC_SIMD_IP}:${IBC_NODE_GRPC_PORT}"
HERMES_MNEMONIC=$(cat < "${ASSETS_DIR}/ibc_net/wallets/hermes1.json" | jq -r ".mnemonic")

config_hermes "${HERMES_FUND_RPC}" "${HERMES_FUND_GRPC}" "${HERMES_SIMD_RPC}" "${HERMES_SIMD_GRPC}"

cp "${BASE_TEMPLATES_DIR}"/configs/nginx.conf "${ASSETS_DIR}"/nginx.conf
sed -i "s/__RPC__/${RPC1_IP}:${RPC1_REST_PORT}/g" "${ASSETS_DIR}/nginx.conf"

cat >>"${DOCKER_COMPOSE}" <<EOL

  ${CONTAINER_PREFIX}tx_runner:
    hostname: ${CONTAINER_PREFIX}tx_runner
    build:
      context: .
      dockerfile: docker/tx_runner.Dockerfile
      args:
        UND_GENESIS_VER: "${UND_GENESIS_VER}"
        IBC_VER: "${IBC_VER}"
        UND_UPGRADE_BRANCH: "${UND_UPGRADE_BRANCH}"
        V_PREFIX: "${V_PREFIX}"
    container_name: ${CONTAINER_PREFIX}tx_runner
    command: >
      /bin/bash -c "
        cd /root &&
        ./scripts/populate_wrapper.sh "${UPGRADE_HEIGHT}" "${RPC1_IP}" "${RPC1_PORT}" ${STORAGE_PURCHASE} "${UPGRADE_PLAN_NAME}" "http://${HERMES_SIMD_RPC}" "${CHAIN_ID}" "${IBC_CHAIN_ID}"
      "
    networks:
      ${DOCKER_NETWORK}:
        ipv4_address: ${TX_RUNNER_IP}
    volumes:
      - ./out/tx_runner:/root/out:rw

  ${CONTAINER_PREFIX}ibc_simd:
    hostname: ${CONTAINER_PREFIX}ibc_simd
    build:
      context: .
      dockerfile: docker/ibc_simd.Dockerfile
      args:
        UND_GENESIS_VER: "${UND_GENESIS_VER}"
        IBC_VER: "${IBC_VER}"
    container_name: ${CONTAINER_PREFIX}ibc_simd
    command: >
      /bin/bash -c "
        cd /root &&
        ./run_ibc_simd.sh
      "
    networks:
      ${DOCKER_NETWORK}:
        ipv4_address: ${IBC_SIMD_IP}
    ports:
      - "${IBC_NODE_P2P_PORT}:${IBC_NODE_P2P_PORT}"
      - "${IBC_NODE_RPC_PORT}:${IBC_NODE_RPC_PORT}"
      - "${IBC_NODE_REST_PORT}:${IBC_NODE_REST_PORT}"
      - "${IBC_NODE_GRPC_PORT}:${IBC_NODE_GRPC_PORT}"
    volumes:
      - ./out/ibc_simd:/root/out:rw

  ${CONTAINER_PREFIX}ibc_hermes:
    hostname: ${CONTAINER_PREFIX}ibc_hermes
    build:
      context: .
      dockerfile: docker/hermes.Dockerfile
      args:
        MNEMONIC: "${HERMES_MNEMONIC}"
        UND_GENESIS_VER: "${UND_GENESIS_VER}"
        CHAIN_ID: "${CHAIN_ID}"
        IBC_VER: "${IBC_VER}"
        IBC_CHAIN_ID: "${IBC_CHAIN_ID}"
        HERMES_VER: "${HERMES_VER}"
    container_name: ${CONTAINER_PREFIX}ibc_hermes
    command: >
      /bin/bash -c "
        cd /root &&
        ./run_hermes.sh "${CHAIN_ID}" "${IBC_CHAIN_ID}"
      "
    networks:
      ${DOCKER_NETWORK}:
        ipv4_address: ${HERMES_IP}
    ports:
      - "3000:3000"
      - "3001:3001"
    volumes:
      - ./out/hermes:/root/out:rw

  ${CONTAINER_PREFIX}proxy:
    hostname: ${CONTAINER_PREFIX}proxy
    container_name: ${CONTAINER_PREFIX}proxy
    build:
      context: .
      dockerfile: docker/proxy.Dockerfile
    networks:
      ${DOCKER_NETWORK}:
        ipv4_address: ${PROXY_IP}
    ports:
      - "1320:1320"

networks:
  ${DOCKER_NETWORK}:
    ipam:
      driver: default
      config:
        - subnet: $SUBNET.0/24
EOL

#########################
# process pre-defined txs
#########################

PRE_DEFINED_TXS=$(get_conf ".apps.und.txs")
MIN_GOV_DEPOSIT=$(cat < "${GLOBAL_TMP_UND_HOME}"/config/genesis.json | jq -r ".app_state.gov.deposit_params.min_deposit[0].amount")

function process_gov_txs() {
  local GOV_TXS
  local TX_ID
  local TX_TITLE
  local TX_DESC
  local TX_PROP_TYPE
  local TX_PROP
  local TX_JSON_FILE
  local PROP_JSON
  GOV_TXS=$(get_conf ".apps.und.txs.gov")
  if [ "$GOV_TXS" != "null" ]; then
    echo "process pre-defined gov txs"
    for row in $(echo "${PRE_DEFINED_TXS}" | jq -r ".gov[] | @base64"); do
      TX_ID=$(_jq "${row}" '.id')
      TX_TITLE=$(_jq "${row}" '.title')
      TX_DESC=$(_jq "${row}" '.description')
      TX_PROP_TYPE=$(_jq "${row}" '.type')
      TX_PROP=$(_jq "${row}" '.proposal')
      TX_JSON_FILE="${ASSETS_TXS_DIR}/gov.${TX_ID}.json"

      if [ "$TX_PROP_TYPE" = "param_change" ]; then
        PROP_JSON=$(cat <<EOF
{
  "title": "${TX_TITLE}",
  "description": "${TX_DESC}",
  "changes": ${TX_PROP},
  "deposit": "${MIN_GOV_DEPOSIT}nund"
}
EOF
)
        echo "${PROP_JSON}" | jq > "${TX_JSON_FILE}"
      fi
    done
  fi
}

#"deposit": [
 #    {
 #      "denom": "nund",
 #      "amount": "${MIN_GOV_DEPOSIT}"
 #    }
 #  ]


# Governance
if [ "$PRE_DEFINED_TXS" != "null" ]; then
  process_gov_txs

  echo "${PRE_DEFINED_TXS}" | jq > "${ASSETS_TXS_DIR}/pre_defined.json"
else
  echo "No pre-defined txs"
fi

rm -rf "${TMP_DIR}"

echo "Done"
