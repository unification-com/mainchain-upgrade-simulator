#!/bin/bash

set -e

# download_genesis_bin
# Checks if the required binary exists in third_party/bin.
# These are used for the initial generation of wallets, configs and genesis etc.
function download_genesis_bin() {
  local L_BIN_T=${1}
  local L_BIN=${2}
  local L_DL_LOC
  local L_TAR

  if [ $L_BIN_T = "und" ]; then
    L_DL_LOC="https://github.com/unification-com/mainchain/releases/download/v${CONF_UND_GENESIS_VER}/und_v${CONF_UND_GENESIS_VER}_linux_x86_64.tar.gz"
    L_TAR="und_v${CONF_UND_GENESIS_VER}_linux_x86_64.tar.gz"
  else
    L_BIN_T="gaiad-v${CONF_IBC_VER}-linux-amd64"
    L_DL_LOC="https://github.com/cosmos/gaia/releases/download/v${CONF_IBC_VER}/${L_BIN_T}"
    L_TAR=""
  fi

  if ! test -f "$L_BIN"; then
    echo "Genesis binary for ${L_BIN_T} not found. Downloading"
    mkdir -p "${BIN_DIR}"/tmp
    cd "${BIN_DIR}"/tmp || exit
    wget "${L_DL_LOC}"
    if [ -n "$L_TAR" ]; then
      tar -zxvf "${L_TAR}"
    fi
    mv "${L_BIN_T}" "${L_BIN}"
    chmod +x "${L_BIN}"
    rm -rf "${BIN_DIR}"/tmp
  fi
}

function download_tomli() {
  if ! test -f "$TOMLI_BIN"; then
    echo "Genesis binary for ${TOMLI_BIN} not found. Downloading"
    mkdir -p "${BIN_DIR}"/tmp
    cd "${BIN_DIR}"/tmp || exit
    wget https://github.com/blinxen/tomli/releases/download/0.3.0/tomli.tar.gz
    tar -zxvf tomli.tar.gz
    mv tomli "${TOMLI_BIN}"
    chmod +x "${TOMLI_BIN}"
    rm -rf "${BIN_DIR}"/tmp
  fi
}

function download_hermes() {
  if ! test -f "$HERMES_BIN"; then
    echo "Genesis binary for ${HERMES_BIN} not found. Downloading"
    mkdir -p "${BIN_DIR}"/tmp
    cd "${BIN_DIR}"/tmp || exit
    wget https://github.com/informalsystems/hermes/releases/download/v"${CONF_HERMES_VER}"/hermes-v"${CONF_HERMES_VER}"-x86_64-unknown-linux-gnu.tar.gz
    tar -zxvf hermes-v"${CONF_HERMES_VER}"-x86_64-unknown-linux-gnu.tar.gz
    mv hermes "${HERMES_BIN}"
    chmod +x "${HERMES_BIN}"
    rm -rf "${BIN_DIR}"/tmp
  fi
}

function download_third_party_binaries() {
  download_genesis_bin "und" "${UND_BIN}"
  download_genesis_bin "gaiad" "${GAIAD_BIN}"
  download_tomli
  download_hermes
}
