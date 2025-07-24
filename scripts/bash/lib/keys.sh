#!/bin/bash

set -e

function create_and_save_key() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ACC_NAME="${3}"
  local L_WALLET_DIR="${4}"
  local L_WALLET_TYPE="${5}"
  local L_MNEMONIC=""
  local L_WALLET_INFO="${L_WALLET_DIR}/${L_ACC_NAME}.json"
  local L_RES=""

  L_RES=$(${L_BIN} keys add "${L_ACC_NAME}" --keyring-backend=test --home="${L_HOME}" --output=json 2>&1)

  L_MNEMONIC=$(echo "${L_RES}" | jq -r ".mnemonic")

  write_key_data "${L_BIN}" "${L_HOME}" "${L_WALLET_INFO}" "${L_ACC_NAME}" "${L_MNEMONIC}" "${L_WALLET_TYPE}"

}

function write_key_data() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_FILE="${3}"
  local L_ACC_NAME="${4}"
  local L_MNEMONIC="${5}"
  local L_WALLET_TYPE="${6}"

  local L_RES=""
  local L_ADDR=""
  local L_VAL_ADDR=""
  local L_CONS_ADDR=""
  local L_PUBKEY=""
  local L_HEX_ADDR=""
  local L_BECH32_PREFIX=""
  local L_KEY=""

  L_RES=$(${L_BIN} keys show "${L_ACC_NAME}" --keyring-backend=test --home="${L_HOME}" --output=json 2>&1)

  L_ADDR=$(echo "${L_RES}" | jq -r ".address")
  L_PUBKEY=$(echo "${L_RES}" | jq -r ".pubkey")

  L_VAL_ADDR=$(${L_BIN} keys show "${L_ACC_NAME}" -a --bech "val" --keyring-backend=test --home="${L_HOME}" 2>&1)
  L_CONS_ADDR=$(${L_BIN} keys show "${L_ACC_NAME}" -a --bech "cons" --keyring-backend=test --home="${L_HOME}" 2>&1)

  L_RES=$(${L_BIN} keys parse "${L_ADDR}" --keyring-backend=test --home="${L_HOME}" --output=json 2>&1)

  L_HEX_ADDR=$(echo "${L_RES}" | jq -r ".bytes")
  L_BECH32_PREFIX="$(echo "${L_RES}" | jq -r ".human")"

  L_KEY=$(cat "${L_HOME}"/keyring-test/${L_ACC_NAME}.info)

  cat >"${L_FILE}" <<EOL
{
  "account": "${L_ACC_NAME}",
  "wallet_type": "${L_WALLET_TYPE}",
  "mnemonic": "${L_MNEMONIC}",
  "address_bech32": "${L_ADDR}",
  "address_hex": "${L_HEX_ADDR}",
  "bech32_prefix": "${L_BECH32_PREFIX}",
  "validator_address": "${L_VAL_ADDR}",
  "consensus_address": "${L_CONS_ADDR}",
  "pubkey": ${L_PUBKEY},
  "key_files": {
    "contents": "${L_KEY}",
    "filename1": "$(echo "$L_HEX_ADDR" | tr '[:upper:]' '[:lower:]').address",
    "filename2": "${L_ACC_NAME}.info"
  }
}
EOL
}

function create_key_from_existing_mnemonic() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ACC_NAME="${3}"
  local L_SRC_WALLET_DIR="${4}"
  local L_DST_WALLET_DIR="${5}"
  local L_WALLET_TYPE="${6}"
  local L_SRC_WALLET_INFO="${L_SRC_WALLET_DIR}/${L_ACC_NAME}.json"
  local L_DST_WALLET_INFO="${L_DST_WALLET_DIR}/${L_ACC_NAME}.json"
  local L_MNEMONIC=""
  local L_RES=""

  L_MNEMONIC=$(cat "${L_SRC_WALLET_INFO}" | jq -r ".mnemonic")

  L_RES=$(yes "${L_MNEMONIC}" | ${L_BIN} keys add "${L_ACC_NAME}" --keyring-backend=test --home "${L_HOME}" --recover --output=json)

  write_key_data "${L_BIN}" "${L_HOME}" "${L_DST_WALLET_INFO}" "${L_ACC_NAME}" "${L_MNEMONIC}" "${L_WALLET_TYPE}"

}

function get_address_from_acc_name() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ACC_NAME="${3}"
  local L_BECH_TYPE="${4}"

  local L_ADDR=""

  L_ADDR=$(${L_BIN} keys show "${L_ACC_NAME}" -a --bech "${L_BECH_TYPE}" --keyring-backend test --keyring-dir "${L_HOME}")
  echo "${L_ADDR}"
}

function get_pubkey_from_acc_name() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_ACC_NAME="${3}"
  local L_RES=""
  local L_PUBKEY=""

  L_RES=$(${L_BIN} keys show "${L_ACC_NAME}" --keyring-backend test --keyring-dir "${L_HOME}" --pubkey)
  L_PUBKEY=$(echo "${L_RES}" | jq -r ".pubkey")
  echo "${L_PUBKEY}"
}

function get_tendermint_validator_pubkey() {
  local L_BIN="${1}"
  local L_HOME="${2}"
  local L_PUBKEY=""
  L_PUBKEY=$(${L_BIN} tendermint show-validator --home "${L_HOME}")
  echo "${L_PUBKEY}"
}
