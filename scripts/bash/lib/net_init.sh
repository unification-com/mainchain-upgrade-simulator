#!/bin/bash

set -e

function init_node() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_CHAIN_ID="${3}"
  local L_MONIKER="${4}"
  ${L_BIN} init "${L_MONIKER}" --home "${L_HOME}" --chain-id "${L_CHAIN_ID}"
}

function config_global_tmp_node() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_CHAIN_ID="${3}"

  ${L_BIN} config set client chain-id "${L_CHAIN_ID}" --home "${L_HOME}"
  ${L_BIN} config set client keyring-backend test --home "${L_HOME}"
  ${L_BIN} config set client output json --home "${L_HOME}"
}

function config_fund_genesis() {
  local L_HOME="${1}"

  # Modify for nund etc.
  sed -i "s/stake/nund/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"voting_period\": \"172800s\"/\"voting_period\": \"90s\"/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"max_deposit_period\": \"172800s\"/\"max_deposit_period\": \"90s\"/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"fee_purchase_storage\": \"5000000000\"/\"fee_purchase_storage\": \"1000000000\"/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"default_storage_limit\": \"50000\"/\"default_storage_limit\": \"100\"/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"max_storage_limit\": \"600000\"/\"max_storage_limit\": \"200\"/g" "${L_HOME}/config/genesis.json"

  # Set unbonding time to 60s for testing (tx_runner bonds & unbonds tokens in test txs)
  sed -i "s/\"unbonding_time\": \"1814400s\"/\"unbonding_time\": \"60s\"/g" "${L_HOME}/config/genesis.json"
#  if [ "$GENESIS_TIME" != "null" ]; then
#    sed -i "s/\"genesis_time\": \".*\"/\"genesis_time\": \"${GENESIS_TIME}\"/g" "${L_HOME}/config/genesis.json"
#  fi
}

function set_fund_enterprise_genesis() {
  local L_HOME="${1}"
  local L_NUM_ACCEPTS="${2}"
  local L_ENT_ADDRESSES="${3}"
  sed -i "s/\"min_accepts\": \"1\"/\"min_accepts\": \"${L_NUM_ACCEPTS}\"/g" "${L_HOME}/config/genesis.json"
  sed -i "s/\"ent_signers\": \"und1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq5x8kpm\"/\"ent_signers\": \"$L_ENT_ADDRESSES\"/g" "${L_HOME}/config/genesis.json"
}

function add_account_to_genesis() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ACC="${3}"
  local L_AMT="${4}"
  local L_ADDR=""

  L_ADDR=$(get_address_from_acc_name "${L_BIN}" "${L_HOME}" "${L_ACC}" "acc")

  ${L_BIN} genesis add-genesis-account "${L_ADDR}" "${L_AMT}" --home="${L_HOME}"
}

function add_wallet_address_to_genesis() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ADDR="${3}"
  local L_AMT="${4}"

  ${L_BIN} genesis add-genesis-account "${L_ADDR}" "${L_AMT}" --home="${L_HOME}"
}

function init_fund_enterprise_accounts() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_WALLET_DIR="${3}"
  local L_NUM="${4}"
  local L_AMNT="${5}"

  local L_ACC_NAME=""
  local L_ENT_ADDR=""
  local L_ENT_ADDRESSES=""

  for (( i=1; i<=L_NUM; i++ ))
  do
    L_ACC_NAME="${TYPE_WALLET_ENTERPRISE}${i}"
    create_and_save_key "${L_BIN}" "${L_HOME}" "${L_ACC_NAME}" "${L_WALLET_DIR}" "${TYPE_WALLET_ENTERPRISE}"
    add_account_to_genesis "${L_BIN}" "${L_HOME}" "${L_ACC_NAME}" "${L_AMNT}nund"
    L_ENT_ADDR=$(get_address_from_acc_name "${L_BIN}" "${L_HOME}" "${L_ACC_NAME}" "acc")
    L_ENT_ADDRESSES+="${L_ENT_ADDR},"
  done

  L_ENT_ADDRESSES=$(echo "${L_ENT_ADDRESSES}" | sed 's/\(.*\),/\1/')
  echo "${L_ENT_ADDRESSES}"
}

function create_accounts_and_add_to_genesis() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_WALLET_DIR="${3}"
  local L_NUM="${4}"
  local L_AMNT="${5}"
  local L_ACC_PREFIX="${6}"
  local L_WALLET_TYPE="${7}"
  local L_ACC_NAME=""

  for (( i=1; i<=L_NUM; i++ ))
  do
    L_ACC_NAME="${L_ACC_PREFIX}${i}"
    create_and_save_key "${L_BIN}" "${L_HOME}" "${L_ACC_NAME}" "${L_WALLET_DIR}" "${L_WALLET_TYPE}"
    add_account_to_genesis "${L_BIN}" "${L_HOME}" "${L_ACC_NAME}" "${L_AMNT}"
  done
}
