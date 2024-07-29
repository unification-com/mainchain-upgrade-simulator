#!/bin/bash

UND_BIN="/usr/local/bin/und_genesis"
UNDOLD_BIN="/usr/local/bin/und_genesis"
UNDNEW_BIN="/usr/local/bin/und_upgrade"
GAIAD_BIN="/usr/local/bin/gaiad"
UPGRADE_HEIGHT=$1
DEVNET_RPC_IP=$2
DEVNET_RPC_PORT=$3
SCRIPT_ALIAS=$4
UPGRADE_PLAN_NAME=$5
IBC_RPC=$6
CHAIN_ID=$7
IBC_CHAIN_ID=$8
DEVNET_RPC_TCP="tcp://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
DEVNET_RPC_HTTP="http://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
BROADCAST_MODE="sync"
GAS_PRICES="25.0nund"
GAIAD_GAS_PRICES="1.0stake"
UND_HOME="/root/.und_cli_txs"
IBC_HOME="/root/.gaiad_cli_txs"

# in DevNet, this will always be derived from "transfer/channel-0/nund"
# See https://tutorials.cosmos.network/tutorials/6-ibc-dev/#how-are-ibc-denoms-derived
IBC_DENOM="ibc/D6CFF2B192E06AFD4CD78859EA7CAD8B82405959834282BE87ABB6B957939618"

IBC_ACCS_FUND=(__POP_TXS_IBC_ACCS_FUND__)
IBC_ACC_SEQUENCESS_FUND=( __POP_TXS_IBC_ACC_SEQUENCESS_FUND__)
IBC_ACCS_GAIAD=(__POP_TXS_IBC_ACCS_GAIAD__)
IBC_ACC_SEQUENCESS_GAIAD=( __POP_TXS_IBC_ACC_SEQUENCESS_GAIAD__)

CURRENT_HEIGHT=0

cp -r "/root/.und_mainchain" "${UND_HOME}"
cp -r "/root/.simapp" "${IBC_HOME}"

printf "[%s] [%s] UPGRADE_HEIGHT=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}"
printf "[%s] [%s] UPGRADE_PLAN_NAME=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_PLAN_NAME}"
printf "[%s] [%s] DEVNET_RPC_TCP=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_TCP}"
printf "[%s] [%s] DEVNET_RPC_HTTP=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_HTTP}"
printf "[%s] [%s] IBC_RPC=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${IBC_RPC}"

function set_und_bin() {
  if [ "$CURRENT_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    UND_BIN=${UNDNEW_BIN}
  else
    UND_BIN=${UNDOLD_BIN}
  fi
}

function set_current_height() {
  CURRENT_HEIGHT=$(curl -s ${DEVNET_RPC_HTTP}/status | jq --raw-output '.result.sync_info.latest_block_height')
}

function check_online() {
  until nc -z "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}";
  do
    printf "[%s] [%s] Upgrade occurring? Waiting for DevNet to come back online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
    sleep 1
  done
}

function print_current_block() {
  set_current_height
  local IS_POST_UPGRADE
  IS_POST_UPGRADE="BEFORE UPGRADE"
  if [ "$CURRENT_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    IS_POST_UPGRADE="AFTER UPGRADE"
  fi
  printf "[%s] [%s] FUND Block: %s (%s)\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${CURRENT_HEIGHT}" "${IS_POST_UPGRADE}"
}

function _jq() {
  echo ${1} | base64 -d | jq -r ${2}
}

function gen_hash() {
  local UUID
  local HASH
  UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  HASH=$(echo "${UUID}" | openssl dgst -sha256)
  local SHA_HASH_ARR=($HASH)
  local SHA_HASH=${SHA_HASH_ARR[1]}
  echo "${SHA_HASH}"
}

function get_bin() {
  local DAEMON=$1
  local EXE
  if [ "$DAEMON" = "und" ]; then
    EXE=${UND_BIN}
  else
    EXE=${GAIAD_BIN}
  fi

  echo "${EXE}"
}

function get_rpc() {
  local DAEMON=$1
  local RPC
  if [ "$DAEMON" = "und" ]; then
    RPC=${DEVNET_RPC_TCP}
  else
    RPC=${IBC_RPC}
  fi

  echo "${RPC}"
}

function get_chian_id() {
  local DAEMON=$1
  local CID
  if [ "$DAEMON" = "und" ]; then
    CID=${CHAIN_ID}
  else
    CID=${IBC_CHAIN_ID}
  fi

  echo "${CID}"
}

function get_gas_prices() {
  local DAEMON=$1
  local GP
  if [ "$DAEMON" = "und" ]; then
    GP=${GAS_PRICES}
  else
    GP=${GAIAD_GAS_PRICES}
  fi

  echo "${GP}"
}

function get_homedir() {
  local DAEMON=$1
  local HOME_DIR
  if [ "$DAEMON" = "und" ]; then
    HOME_DIR=${UND_HOME}
  else
    HOME_DIR=${IBC_HOME}
  fi

  echo "${HOME_DIR}"
}

function get_addr() {
  set_und_bin
  local ACC=$1
  local DAEMON=$2
  local EXE
  local ADDR
  local HOME_DIR
  EXE=$(get_bin "${DAEMON}")
  HOME_DIR=$(get_homedir "${DAEMON}")

  ADDR=$(${EXE} keys show $ACC -a --keyring-backend test --keyring-dir "${HOME_DIR}")
  echo "${ADDR}"
}

function get_base_flags() {
  local DAEMON=$1
  local RPC
  local CID
  local HOME_DIR
  RPC=$(get_rpc "${DAEMON}")
  CID=$(get_chian_id "${DAEMON}")
  HOME_DIR=$(get_homedir "${DAEMON}")

  local FLAGS="--broadcast-mode ${BROADCAST_MODE} --chain-id ${CID} --node ${RPC} --home ${HOME_DIR} --output json --gas auto --gas-adjustment 1.5 --keyring-backend test --yes"
  echo "${FLAGS}"
}

function get_gas_flags() {
  local DAEMON=$1
  local FLAGS="--gas-prices $(get_gas_prices ${DAEMON})"
  echo "${FLAGS}"
}

function get_query_flags() {
  local HOME_DIR
  HOME_DIR=$(get_homedir "${DAEMON}")
  local FLAGS="--node ${DEVNET_RPC_TCP} --chain-id ${CHAIN_ID} --output json --home ${HOME_DIR}"
  echo "${FLAGS}"
}

function check_accounts_exist() {
  local ACC=${1}
  local DAEMON=${2}
  local EXE
  local HOME_DIR
  HOME_DIR=$(get_homedir "${DAEMON}")
  set_und_bin
  EXE=$(get_bin "${DAEMON}")

  local TMP="${EXE} keys show --keyring-dir=${HOME_DIR} --keyring-backend=test $ACC"
  printf "[%s] [%s] %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TMP}"

  if { ${EXE} keys show --keyring-dir=${HOME_DIR} --keyring-backend=test $ACC 2>&1 >&3 3>&- | grep '^' >&2; } 3>&1; then
    echo "${ACC} acc does not seem to exist in keyring. Exiting"
    exit 1
  else
    printf "[%s] [%s] Found %s in keyring\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${1}"
  fi
}

function get_curr_acc_sequence() {
  set_und_bin
  local ACC=$1
  local DAEMON=$2
  local RPC
  local CID
  local EXE
  local HOME_DIR
  EXE=$(get_bin "${DAEMON}")
  RPC=$(get_rpc "${DAEMON}")
  CID=$(get_chian_id "${DAEMON}")
  HOME_DIR=$(get_homedir "${DAEMON}")

  local RES=$(${EXE} query account $(get_addr "${ACC}" "${DAEMON}") --node=${RPC} --chain-id=${CID} --output=json)
  local CURR=$(echo "${RES}" | jq --raw-output '.sequence')
  local CURR_INT=$(awk "BEGIN {print $CURR}")
  echo "${CURR_INT}"
}

function update_user_acc_sequences() {
  printf "[%s] [%s] update user acc sequences\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  for i in ${!IBC_ACCS_FUND[@]}
  do
    IBC_ACC_SEQUENCESS_FUND[$i]=$(get_curr_acc_sequence "${IBC_ACCS_FUND[$i]}" "und")
  done

  for i in ${!IBC_ACCS_GAIAD[@]}
  do
    IBC_ACC_SEQUENCESS_GAIAD[$i]=$(get_curr_acc_sequence "${IBC_ACCS_GAIAD[$i]}" "gaiad")
  done
}

function get_balance() {
  set_und_bin
  local ACC=$1
  local DAEMON=$2
  local RPC
  local CID
  local EXE
  local RES
  local AMT
  local DEN
  EXE=$(get_bin "${DAEMON}")
  RPC=$(get_rpc "${DAEMON}")
  CID=$(get_chian_id "${DAEMON}")

  RES=$(${EXE} query bank balances $(get_addr "${ACC}" "${DAEMON}") --node=${RPC} --chain-id=${CID} --output=json)

  for row in $(echo "${RES}" | jq -r '.balances[] | @base64'); do
    AMT=$(_jq ${row} ".amount")
    DEN=$(_jq ${row} ".denom")
    printf "[%s] [%s] %s balance for %s: %s %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DAEMON}" "${ACC}" "${AMT}" "${DEN}"
  done

}

function get_all_balances() {
  for i in ${!IBC_ACCS_FUND[@]}
  do
    GAIAD_ACC=${IBC_ACCS_GAIAD[$i]}
    UND_ACC=${IBC_ACCS_FUND[$i]}
    printf "[%s] [%s] get und balances for %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UND_ACC}"
    get_balance "${UND_ACC}" "und"
    printf "[%s] [%s] get gaiad balances for %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${GAIAD_ACC}"
    get_balance "${GAIAD_ACC}" "gaiad"
  done
}

function get_denom_balance() {
  local WALLET_ADDR=${1}
  local DENOM=${2}
  local DAEMON=${3}
  local RPC
  local CID
  local EXE
  local RES
  local AMT
  EXE=$(get_bin "${DAEMON}")
  RPC=$(get_rpc "${DAEMON}")
  CID=$(get_chian_id "${DAEMON}")

  RES=$(${EXE} query bank balances "${WALLET_ADDR}" --node "${RPC}" --chain-id "${CID}" --denom "${DENOM}" --output=json)

  AMT=$(echo "${RES}" | jq -r '.amount')
  echo "${AMT}"
}

function update_all_acc_sequences() {
  update_user_acc_sequences
}

function check_ibc_channel_exists() {
  set_und_bin
  local DAEMON=$1
  local RES
  local TOT_CH
  local RPC
  local CID
  local EXE

  EXE=$(get_bin "${DAEMON}")
  RPC=$(get_rpc "${DAEMON}")
  RES=$(${EXE} query ibc channel channels --node ${RPC} --output json)
  TOT_CH=$(echo "${RES}" | jq ".channels | length")

  echo "${TOT_CH}"
}

function process_tx_log() {
  local LOG_C=${1}

  local RAW_LOG=$(echo ${LOG_C} | jq -r ".raw_log")
  local TX_HASH=$(echo ${LOG_C} | jq -r ".txhash")
  if [ "$RAW_LOG" = "[]" ]; then
    printf "[%s] [%s] Tx submitted in hash: %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TX_HASH}"
  else
    printf "[%s] [%s] ERROR: (%s) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TX_HASH}" "${RAW_LOG}"
  fi
}

function tx_success() {
  local RAW_LOG=$(echo ${1} | jq -r ".raw_log")
  local SUCCESS=0
  if [ "$RAW_LOG" = "[]" ]; then
    SUCCESS=1
  fi
  echo "${SUCCESS}"
}

function send_ibc_fund_to_gaiad() {
  set_und_bin
  printf "[%s] [%s] SEND FROM FUND TO GAIAD\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  for i in ${!IBC_ACCS_FUND[@]}
  do
    TO_ACC=${IBC_ACCS_GAIAD[$i]}
    FROM_ACC=${IBC_ACCS_FUND[$i]}

    FROM_ACC_SEQ=${IBC_ACC_SEQUENCESS_FUND[$i]}
    RND_AMOUNT=$(head -200 /dev/urandom | cksum | cut -f1 -d " ")
    RND_AMOUNT_MUL=$(awk "BEGIN {print $RND_AMOUNT*(10000)}")
    AMOUNT="${RND_AMOUNT_MUL}nund"

    printf "[%s] [%s] send %s from %s to %s (%s)\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${AMOUNT}" "${FROM_ACC}" "${TO_ACC}" $(get_addr ${TO_ACC} "gaiad")

    RES=$(${UND_BIN} tx ibc-transfer transfer transfer channel-0 $(get_addr ${TO_ACC} "gaiad") ${AMOUNT} --from ${FROM_ACC} $(get_base_flags "und") $(get_gas_flags "und") --sequence "${FROM_ACC_SEQ}")
    process_tx_log "${RES}"
  done
}

function send_ibc_fund_from_gaiad() {
  printf "[%s] [%s] SEND FROM GAIAD TO FUND\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  for i in ${!IBC_ACCS_GAIAD[@]}
    do
      TO_ACC=${IBC_ACCS_FUND[$i]}
      FROM_ACC=${IBC_ACCS_GAIAD[$i]}

      FROM_ACC_SEQ=${IBC_ACC_SEQUENCESS_GAIAD[$i]}

      IBC_BALANCE=$(get_denom_balance $(get_addr "${FROM_ACC}" "gaiad") "${IBC_DENOM}" "gaiad")
      # 1. print current balance
      # 2. subtract random amount
      # 3. send modified amount

      if [ "$IBC_BALANCE" -gt "10" ]; then
#        RND_AMOUNT=$(head -200 /dev/urandom | cksum | cut -f1 -d " ")
#        if [ "$RND_AMOUNT" -lt "$IBC_BALANCE" ]; then
#          SEND_AMOUNT=$(awk "BEGIN {print $IBC_BALANCE-$RND_AMOUNT}")
#        else
#          SEND_AMOUNT=$(awk "BEGIN {print $IBC_BALANCE-10}")
#        fi
        SEND_AMOUNT=$(awk "BEGIN {print $IBC_BALANCE-10}")
        AMOUNT="${SEND_AMOUNT}${IBC_DENOM}"

        printf "[%s] [%s] send %s from %s to %s (%s)\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${AMOUNT}" $(get_addr ${FROM_ACC} "gaiad") "${TO_ACC}" $(get_addr ${TO_ACC} "und")

        RES=$(${GAIAD_BIN} tx ibc-transfer transfer transfer channel-0 $(get_addr ${TO_ACC} "und") ${AMOUNT} --from ${FROM_ACC} $(get_base_flags "gaiad") $(get_gas_flags "gaiad") --sequence "${FROM_ACC_SEQ}")
        process_tx_log "${RES}"
      else
        printf "[%s] [%s] not enough balance to send from %s. IBC balance: %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${FROM_ACC}" "${IBC_BALANCE}"
      fi
    done
}

for i in ${!IBC_ACCS_FUND[@]}
do
  check_accounts_exist "${IBC_ACCS_FUND[$i]}" "und"
done

for i in ${!IBC_ACCS_GAIAD[@]}
do
  check_accounts_exist "${IBC_ACCS_GAIAD[$i]}" "gaiad"
done

# check IBC channel exists
#

# Wait for Node1 to come online
printf "[%s] [%s] Waiting for DevNet RPC to come online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
until nc -z "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}";
do
  printf "[%s] [%s] Waiting for DevNet RPC to come online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
  sleep 1
done

printf "[%s] [%s] RPC is online\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

# Wait for first block
until [ $(curl -s ${DEVNET_RPC_HTTP}/status | jq --raw-output '.result.sync_info.latest_block_height') -ge 2 ]
do
  printf "[%s] [%s] Waiting for DevNet Block #2\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  sleep 1
done

printf "[%s] [%s] Block >= 2 committed\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

printf "[%s] [%s] Checking IBC channels\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

until [ $(check_ibc_channel_exists "und") -ge 1 ]
do
  print_current_block
  printf "[%s] [%s] Waiting for IBC channel creation on FUND\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  sleep 5
done

until [ $(check_ibc_channel_exists "gaiad") -ge 1 ]
do
  print_current_block
  printf "[%s] [%s] Waiting for IBC channel creation on gaiad\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  sleep 5
done

TOTAL_CHANNELS_UND=$(check_ibc_channel_exists "und")
TOTAL_CHANNELS_GAIAD=$(check_ibc_channel_exists "gaiad")

print_current_block
printf "[%s] [%s] Total FUND IBC channels = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TOTAL_CHANNELS_UND}"
printf "[%s] [%s] Total gaiad IBC channels = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TOTAL_CHANNELS_GAIAD}"

printf "[%s] [%s] Running transactions\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

START_TIME=$(date +%s)

update_all_acc_sequences

while true
do
  sleep 10s
  check_online
  print_current_block
  get_all_balances
  set_current_height
  set_und_bin
  update_all_acc_sequences

  # send some FUND over IBC
  print_current_block
  get_all_balances
  send_ibc_fund_to_gaiad
  sleep 7s
  update_all_acc_sequences

  # send IBC denom from gaiad to FUND
  sleep 20s
  print_current_block
  get_all_balances
  send_ibc_fund_from_gaiad
  update_all_acc_sequences
done

printf "[%s] [%s] Finished transactions\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

}