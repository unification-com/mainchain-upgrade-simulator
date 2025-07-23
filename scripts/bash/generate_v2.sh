#!/bin/bash

set -e

BASE_DIR="$(pwd)"
SCRIPT_LIB_DIR="${BASE_DIR}/scripts/bash/lib"
CONFIG="${BASE_DIR}/config.json"

if ! test -f "$CONFIG"; then
  echo "config.json not found. Exiting"
  exit 1
fi

function get_conf() {
  local P=${1}
  cat < "${CONFIG}" | jq -r "${P}"
}

# include lib scripts
source "${SCRIPT_LIB_DIR}/includes.sh"

# initialise build directories
init_generated_dirs
init_third_party_dir
init_docker

# Check binaries required for generating exist
download_third_party_binaries

cd "${BASE_DIR}" || exit

# 1. init 1 dummy node for each network

init_node "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${CONF_CHAIN_ID}" "global"
${UND_BIN} config chain-id "${CONF_CHAIN_ID}" --home "${TMP_GLOBAL_UND_HOME}"
${UND_BIN} config keyring-backend test --home "${TMP_GLOBAL_UND_HOME}"
${UND_BIN} config output json --home "${TMP_GLOBAL_UND_HOME}"

config_fund_genesis "${TMP_GLOBAL_UND_HOME}"

init_node "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${CONF_IBC_CHAIN_ID}" "global"
config_global_tmp_node "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${CONF_IBC_CHAIN_ID}"

# 2. init keys and accounts for both networks, save mnemonics to JSON
echo "configure FUND enterprise module"
T_ENT_ADDRESSES=$(init_fund_enterprise_accounts "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_ENT_SIGNERS}" "${CONF_ACCOUNT_START_NUND}")
set_fund_enterprise_genesis "${TMP_GLOBAL_UND_HOME}" "${CONF_NUM_ENT_ACCEPTS}" "${T_ENT_ADDRESSES}"

# Validators
echo "create FUND validator accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_VALIDATORS}" "${CONF_ACCOUNT_START_NUND}nund" "${PREFIX_NODE_VALIDATOR}" "${TYPE_WALLET_VALIDATOR}"

echo "create gaiad validator accounts"
create_accounts_and_add_to_genesis "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${ASSETS_WALLETS_DIR_GAIAD}" "1" "${CONF_ACCOUNT_START_NUND}stake" "${PREFIX_NODE_VALIDATOR}" "${TYPE_WALLET_VALIDATOR}"

# Wrkchains
echo "create wrkchain test accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_WRKCHAINS}" "${CONF_ACCOUNT_START_NUND}nund" "${TYPE_WALLET_WRKCHAIN}" "${TYPE_WALLET_WRKCHAIN}"

# Beacons
echo "create beacon test accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_BEACONS}" "${CONF_ACCOUNT_START_NUND}nund" "${TYPE_WALLET_BEACON}" "${TYPE_WALLET_BEACON}"

# Generic test
echo "create generic test accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_TEST_ACCS}" "${CONF_ACCOUNT_START_NUND}nund" "${TYPE_WALLET_TEST}" "${TYPE_WALLET_TEST}"

# Payment stream senders
echo "create payment stream sender test accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_PAYMENT_STREAMS}" "${CONF_ACCOUNT_START_NUND}nund" "${TYPE_WALLET_PAYMENT_STREAM_SENDER}" "${TYPE_WALLET_PAYMENT_STREAM_SENDER}"

# Payment Stream receivers
echo "create payment stream receiver test accounts"
create_accounts_and_add_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_WALLETS_DIR_UND}" "${CONF_NUM_PAYMENT_STREAMS}" "${CONF_ACCOUNT_START_NUND}nund" "${TYPE_WALLET_PAYMENT_STREAM_RECEIVER}" "${TYPE_WALLET_PAYMENT_STREAM_RECEIVER}"

# IBC Test accounts
echo "create ibc test accounts"
for (( i=1; i<=CONF_NUM_IBC_ACCOUNTS; i++ ))
do
  T_IBC_ACC_NAME="ibc${i}"
  create_and_save_key "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${T_IBC_ACC_NAME}" "${ASSETS_WALLETS_DIR_UND}" "${TYPE_WALLET_IBC}"
  add_account_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${T_IBC_ACC_NAME}" "${CONF_ACCOUNT_START_NUND}nund"

  create_key_from_existing_mnemonic "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${T_IBC_ACC_NAME}" "${ASSETS_WALLETS_DIR_UND}" "${ASSETS_WALLETS_DIR_GAIAD}" "${TYPE_WALLET_IBC}"
  add_account_to_genesis "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${T_IBC_ACC_NAME}" "${CONF_ACCOUNT_START_NUND}stake"
done

echo "create hermes relayer accounts"
create_and_save_key "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "hermes1" "${ASSETS_WALLETS_DIR_UND}" "${TYPE_WALLET_HERMES}"
add_account_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "hermes1" "${CONF_ACCOUNT_START_NUND}nund"
create_key_from_existing_mnemonic "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "hermes1" "${ASSETS_WALLETS_DIR_UND}" "${ASSETS_WALLETS_DIR_GAIAD}" "${TYPE_WALLET_HERMES}"
add_account_to_genesis "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "hermes1" "${CONF_ACCOUNT_START_NUND}stake"

# Statically defined accounts
if [ "$CONF_STATIC_ACCOUNTS" != "null" ]; then
  echo "process pre-defined FUND static wallets"
  for row in $(echo "${CONF_ACC_OBJ}" | jq -r ".static[] | @base64"); do
    T_WA=$(_jq "${row}" '.address')
    T_NUND=$(_jq "${row}" '.nund')
    add_wallet_address_to_genesis "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${T_WA}" "${T_NUND}nund"
  done
fi

if [ "$CONF_IBC_STATIC_ACCOUNTS" != "null" ]; then
  echo "process pre-defined IBC static wallets"
  for row in $(echo "${CONF_IBC_ACC_OBJ}" | jq -r ".static[] | @base64"); do
    T_WA=$(_jq "${row}" '.address')
    T_STAKE=$(_jq "${row}" '.stake')
    add_wallet_address_to_genesis "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "${T_WA}" "${T_STAKE}stake"
  done
fi

# 3. create validators and validator nodes. Run gentx and collect gentxs for both networks
# FUND validators
echo "create FUND validator nodes"
for (( i=1; i<=CONF_NUM_VALIDATORS; i++ ))
do
  T_MONIKER="${PREFIX_NODE_VALIDATOR}${i}"

  create_node "${UND_BIN}" "${ASSETS_NODES_FUND_DIR}" "${CONF_CHAIN_ID}" "${T_MONIKER}" "${GENERATED_NETWORK_DIR_UND}" "${TYPE_NODE_VALIDATOR}"
  create_validator "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}" "${i}" "${T_MONIKER}" "nund" "${ASSETS_WALLETS_DIR_UND}" "${GENERATED_NETWORK_DIR_UND}" "yes"
done

collect_gentxs "${UND_BIN}" "${TMP_GLOBAL_UND_HOME}"

echo "create ibc chain validator node"
create_node "${GAIAD_BIN}" "${ASSETS_NODES_GAIAD_DIR}" "${CONF_IBC_CHAIN_ID}" "validator1" "${GENERATED_NETWORK_DIR_GAIAD}" "${TYPE_NODE_VALIDATOR}"
create_validator "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}" "1" "validator1" "stake" "${ASSETS_WALLETS_DIR_GAIAD}" "${GENERATED_NETWORK_DIR_GAIAD}" "no"
collect_gentxs "${GAIAD_BIN}" "${TMP_GLOBAL_GAID_HOME}"

# 4 create all other nodes for both networks
# sentries
echo "create FUND sentry nodes"
for (( i=1; i<=CONF_NUM_SENTRIES; i++ ))
do
  T_MONIKER="${PREFIX_NODE_SENTRY}${i}"
  create_node "${UND_BIN}" "${ASSETS_NODES_FUND_DIR}" "${CONF_CHAIN_ID}" "${T_MONIKER}" "${GENERATED_NETWORK_DIR_UND}" "${TYPE_NODE_SENTRY}"
done

# seeds
echo "create FUND seed nodes"
for (( i=1; i<=CONF_NUM_SEEDS; i++ ))
do
  T_MONIKER="${PREFIX_NODE_SEED}${i}"
  create_node "${UND_BIN}" "${ASSETS_NODES_FUND_DIR}" "${CONF_CHAIN_ID}" "${T_MONIKER}" "${GENERATED_NETWORK_DIR_UND}" "${TYPE_NODE_SEED}"
done

# rpcs
echo "create FUND rpc nodes"
for (( i=1; i<=CONF_NUM_RPCS; i++ ))
do
  T_MONIKER="${PREFIX_NODE_RPC}${i}"
  create_node "${UND_BIN}" "${ASSETS_NODES_FUND_DIR}" "${CONF_CHAIN_ID}" "${T_MONIKER}" "${GENERATED_NETWORK_DIR_UND}" "${TYPE_NODE_RPC}"
done

echo "create ibc rpc node"
create_node "${GAIAD_BIN}" "${ASSETS_NODES_GAIAD_DIR}" "${CONF_IBC_CHAIN_ID}" "rpc1" "${GENERATED_NETWORK_DIR_GAIAD}" "${TYPE_NODE_RPC}"

# 5. configure FUND network (config.toml, app.toml etc.)

# copy genesis files to assets & configure node config.toml/app.toml
echo "configure fund"
configure_nodes "${GENERATED_NETWORK_DIR_UND}" "${TMP_GLOBAL_UND_HOME}" "${ASSETS_NODES_FUND_DIR}" "25.0nund"

echo "configure gaiad"
configure_nodes "${GENERATED_NETWORK_DIR_GAIAD}" "${TMP_GLOBAL_GAID_HOME}" "${ASSETS_NODES_GAIAD_DIR}" "0stake"

echo "add nodes to docker-compose"
generate_docker_compose_fund_nodes
generate_docker_compose_ibc_nodes

# 6. init/configure hermes
echo "configure hermes"
config_hermes
generate_docker_compose_hermes

# 7. generate tx_runner
generate_tx_runner_dotenv
generate_upgrade_tx

# 8. configure nginx proxy & finalise network docker-compose.yaml
echo "configure compose network"
set_docker_compose_network
generate_network_overview

# 9. clean up tmp directories
rm -rf "${TMP_DIR}"
