#!/bin/bash

#########################################################################
# A script for generating and broadcasting some test transactions for   #
# populating DevNet                                                     #
#                                                                       #
# Note: the script assumes the accounts in Docker/README.md have been   #
#       imported into the keychain, jq is installed, and "make build"   #
#       has been run.                                                   #
#########################################################################

UND_BIN="/usr/local/bin/und_genesis"
UNDOLD_BIN="/usr/local/bin/und_genesis"
UNDNEW_BIN="/usr/local/bin/und_upgrade"
UPGRADE_HEIGHT=$1
DEVNET_RPC_IP=$2
DEVNET_RPC_PORT=$3
SCRIPT_ALIAS=$4
STORAGE_PURCHASE=$5
CHAIN_ID=$6
CURRENT_HEIGHT=0
PRE_UPGRADE_CHECK_HEIGHT=$(awk "BEGIN {print $UPGRADE_HEIGHT-1}")
PURCHASE_STORAGE_HEIGHT=$(awk "BEGIN {print $UPGRADE_HEIGHT+10}")
DEVNET_RPC_TCP="tcp://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
DEVNET_RPC_HTTP="http://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
BROADCAST_MODE="sync"
GAS_PRICES="25.0nund"
UPPER_CASE_HASH=0
UND_HOME="/root/.und_cli_beacons_wrkchains"

# Account names as imported into undcli keys
ENT_ACC="ent1"
ENT_ACC_SEQ=0
USER_ACCS=( __POP_B_WC_ACCS__)
TYPES=( __POP_B_WC_TYPES__)
ACC_SEQUENCESS=( __POP_B_WC_ACC_SEQUENCESS__)
WC_HEIGHTS_BEACON_TIMESTAMPS=( __POP_B_WC_WC_HEIGHTS_BEACON_TIMESTAMPS__)
HAS_PURCHASED_STORAGE=( __POP_B_WC_HAS_PURCHASED_STORAGE__)

KEYRING_MIGRATED=0

cp -r "/root/.und_mainchain" "${UND_HOME}"

sleep 1s

printf "[%s] [%s] UPGRADE_HEIGHT=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}"
printf "[%s] [%s] PRE_UPGRADE_CHECK_HEIGHT=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PRE_UPGRADE_CHECK_HEIGHT}"
printf "[%s] [%s] PURCHASE_STORAGE_HEIGHT=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PURCHASE_STORAGE_HEIGHT}"
printf "[%s] [%s] STORAGE_PURCHASE=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${STORAGE_PURCHASE}"

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

function _jq() {
  echo ${1} | base64 -d | jq -r ${2}
}

function _jq_raw {
  echo ${1} | jq -r ${2}
}

function check_online() {
  until nc -z "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}";
  do
    printf "[%s] [%s] Upgrade occurring? Waiting for DevNet to come back online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
    sleep 1
  done
}

gen_hash() {
  local UPPER_CASE_HASH=${1:-$UPPER_CASE_HASH}
  local UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  local HASH=$(echo "${UUID}" | openssl dgst -sha256)
  local SHA_HASH_ARR=($HASH)
  local SHA_HASH=${SHA_HASH_ARR[1]}
  if [ $UPPER_CASE_HASH -eq 1 ]
  then
    echo "${SHA_HASH^^}"
  else
    echo "${SHA_HASH}"
  fi
}

get_addr() {
  set_und_bin
  local ADDR=$(${UND_BIN} keys show $1 -a --keyring-backend=test --keyring-dir=${UND_HOME})
  echo "${ADDR}"
}

get_base_flags() {
  local BROADCAST=${1:-$BROADCAST_MODE}
  local FLAGS="--broadcast-mode ${BROADCAST} --chain-id ${CHAIN_ID} --node ${DEVNET_RPC_TCP} --output json --home ${UND_HOME} --gas auto --gas-adjustment 1.6 --keyring-backend test --yes"
  echo "${FLAGS}"
}

get_gas_flags() {
  local FLAGS="--gas-prices ${GAS_PRICES}"
  echo "${FLAGS}"
}

function get_query_flags() {
  local FLAGS="--node ${DEVNET_RPC_TCP} --chain-id ${CHAIN_ID} --output=json --home ${UND_HOME}"
  echo "${FLAGS}"
}

function query_params() {
  local TYPE=$1
  local CHECK_HEIGHT=$2
  local UND_BIN_TO_USE=${UND_BIN}
  if [ "$CHECK_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    UND_BIN=${UNDNEW_BIN}
  else
    UND_BIN=${UNDOLD_BIN}
  fi

  local RES=$(${UND_BIN_TO_USE} query "${TYPE}" "params" "--height" "${CHECK_HEIGHT}" $(get_query_flags))
  echo "${RES}"
}

function query_beacon_wrkchain() {
  local TYPE=$1
  local ID=$2
  local CHECK_HEIGHT=$3
  local LOWEST="0"
  local HIGHEST="0"
  local NUM="0"
  local LIMIT="0"
  local UND_BIN_TO_USE=${UND_BIN}

  if [ "$CHECK_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    UND_BIN=${UNDNEW_BIN}
  else
    UND_BIN=${UNDOLD_BIN}
  fi

  local RES=$(${UND_BIN_TO_USE} query "${TYPE}" "${TYPE}" "${ID}" "--height" "${CHECK_HEIGHT}" $(get_query_flags))

  if [ "$TYPE" = "wrkchain" ]; then
    HIGHEST=$(_jq_raw "${RES}" '.wrkchain.lastblock')
    LOWEST=$(_jq_raw "${RES}" '.wrkchain.lowest_height')
    NUM=$(_jq_raw "${RES}" '.wrkchain.num_blocks')
  else
    HIGHEST=$(_jq_raw "${RES}" '.beacon.last_timestamp_id')
    LOWEST=$(_jq_raw "${RES}" '.beacon.first_id_in_state')
    NUM=$(_jq_raw "${RES}" '.beacon.num_in_state')
  fi

  if [ "$CHECK_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    local STR_RES=$(${UND_BIN_TO_USE} query "${TYPE}" storage "${ID}" "--height" "${CHECK_HEIGHT}" $(get_query_flags))
    LIMIT=$(_jq_raw "${STR_RES}" '.current_limit')
    echo "num: ${NUM}, lowest: ${LOWEST}, highest: ${HIGHEST}, limit: ${LIMIT}"
  else
    echo "num: ${NUM}, lowest: ${LOWEST}, highest: ${HIGHEST}"
  fi
}

function query_spent_efund() {
  local ADDR_TO_QUERY=$1
  local CHECK_HEIGHT=$2

  local RES=$(${UNDNEW_BIN} query enterprise spent "${ADDR_TO_QUERY}" "--height" "${CHECK_HEIGHT}" $(get_query_flags))

  local SPENT_NUND=$(_jq_raw "${RES}" '.amount.amount')
  local SPENT_FUND=$(awk "BEGIN {print $SPENT_NUND / 1000000000}")

  echo "${ADDR_TO_QUERY} ${SPENT_NUND} (${SPENT_FUND})"
}

function check_accounts_exist() {
  set_und_bin
  if { ${UND_BIN} keys show  --keyring-dir ${UND_HOME} --keyring-backend test $1 2>&1 >&3 3>&- | grep '^' >&2; } 3>&1; then
    echo "${1} does not seem to exist in keyring. Exiting"
    exit 1
  else
    printf "[%s] [%s] Found %s in keyring\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${1}"
  fi
}

function get_curr_acc_sequence() {
  set_und_bin
  local ACC=$1
  local RES=$(${UND_BIN} query account $(get_addr ${ACC}) $(get_query_flags))
  local CURR=$(echo "${RES}" | jq --raw-output '.sequence')
  local CURR_INT=$(awk "BEGIN {print $CURR}")
  echo "${CURR_INT}"
}

function process_tx_log() {
  local LOG_C=${1}
  local RAW_LOG=$(echo ${LOG_C} | jq -r ".raw_log")
  local TX_HASH=$(echo ${LOG_C} | jq -r ".txhash")
#  printf "[%s] [%s] LOG: (%s) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${LOG_C}"
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

function update_acc_sequence() {
  local TX_SUCCESS=${1}
  local ACC=${2}
  local IDX=${3}
  local LAST_USED_ACC_SEQ=${4}
  if [ "$TX_SUCCESS" = "0" ]; then
    CURR_ACC_SEQ=$(get_curr_acc_sequence "${ACC}")
    printf "[%s] [%s] LAST_USED_ACC_SEQ=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${LAST_USED_ACC_SEQ}"
    printf "[%s] [%s] CURR_ACC_SEQ=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${CURR_ACC_SEQ}"
    ACC_SEQUENCESS[$IDX]=$(awk "BEGIN {print $CURR_ACC_SEQ}")
  else
    ACC_SEQUENCESS[$IDX]=$(awk "BEGIN {print $LAST_USED_ACC_SEQ+1}")
  fi
}

check_accounts_exist ${ENT_ACC}

for i in ${!USER_ACCS[@]}
do
  check_accounts_exist "${USER_ACCS[$i]}"
done

# Wait for Node1 to come online
printf "[%s] [%s] Waiting for DevNet Node1 to come online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
until nc -z "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}";
do
  printf "[%s] [%s] Waiting for DevNet Node1 to come online %s:%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}"
  sleep 1
done

printf "[%s] [%s] Node1 is online\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

# Wait for first block
until [ $(curl -s ${DEVNET_RPC_HTTP}/status | jq --raw-output '.result.sync_info.latest_block_height') -ge 1 ]
do
  printf "[%s] [%s] Waiting for DevNet Block #1\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  sleep 1
done

printf "[%s] [%s] Block >= 1 committed\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
printf "[%s] [%s] Running transactions\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

START_TIME=$(date +%s)

ENT_ACC_SEQ=$(get_curr_acc_sequence "${ENT_ACC}")

for i in ${!USER_ACCS[@]}
do
  ACC=${USER_ACCS[$i]}
  CURR_SEQ=$(get_curr_acc_sequence "${ACC}")
  ACC_SEQUENCESS[$i]=${CURR_SEQ}
done

for i in ${!USER_ACCS[@]}
do
  set_und_bin
  ACC=${USER_ACCS[$i]}
  IS_WHITELISTED_RES=$(${UND_BIN} query enterprise whitelisted $(get_addr ${ACC}) $(get_query_flags))
  IS_WHITELISTED=$(_jq_raw "${IS_WHITELISTED_RES}" '.whitelisted')
  printf "[%s] [%s] %s IS_WHITELISTED=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" "${IS_WHITELISTED}"
  if [ "$IS_WHITELISTED" = "true" ]; then
    printf "[%s] [%s] %s already whitelisted\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}"
  else
    printf "[%s] [%s] Whitelist %s for Enterprise POs %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" "$(get_addr ${ACC})"
    RES=$(${UND_BIN} tx enterprise whitelist add $(get_addr ${ACC}) --from ${ENT_ACC} $(get_base_flags) $(get_gas_flags) --sequence ${ENT_ACC_SEQ})
    process_tx_log "${RES}"
    ENT_ACC_SEQ=$(awk "BEGIN {print $ENT_ACC_SEQ+1}")
    sleep 1s
  fi
done

printf "[%s] [%s] Done. Wait for approx. 1 block\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
sleep 7s

for i in ${!USER_ACCS[@]}
do
  set_und_bin
  ACC=${USER_ACCS[$i]}
  ACC_SEQ=${ACC_SEQUENCESS[$i]}
  printf "[%s] [%s] %s raise Enterprise POs - %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" $(get_addr ${ACC})
  RES=$(${UND_BIN} tx enterprise purchase 10000000000000000nund --from ${ACC} $(get_base_flags) $(get_gas_flags) --sequence "${ACC_SEQ}")
  process_tx_log "${RES}"
  ACC_SEQUENCESS[$i]=$(awk "BEGIN {print $ACC_SEQ+1}")
done

printf "[%s] [%s] Done. Wait for approx. 2 blocks\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
sleep 12s

set_und_bin

RAISED_POS=$(${UND_BIN} query enterprise orders $(get_query_flags))

for row in $(echo "${RAISED_POS}" | jq -r ".purchase_orders[] | @base64"); do
  set_und_bin
  POID=$(_jq "${row}" '.id')
  PO_STATUS=$(_jq "${row}" '.status')
  printf "[%s] [%s] Process Enterprise PO %s - status=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${POID}" "${PO_STATUS}"
  if [ "$PO_STATUS" = "STATUS_RAISED" ]; then
    RES=$(${UND_BIN} tx enterprise process ${POID} accept --from ${ENT_ACC} $(get_base_flags) $(get_gas_flags) --sequence ${ENT_ACC_SEQ})
    process_tx_log "${RES}"
    ENT_ACC_SEQ=$(awk "BEGIN {print $ENT_ACC_SEQ+1}")
    sleep 1s
  fi
done

printf "[%s] [%s] Done. Wait for approx. 2 blocks\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
sleep 12s

for i in ${!USER_ACCS[@]}
do
  set_und_bin
  ACC=${USER_ACCS[$i]}
  ACC_SEQ=${ACC_SEQUENCESS[$i]}
  TYPE=${TYPES[$i]}
  MONIKER="${TYPE}_${ACC}"
  GEN_HASH="0x$(gen_hash)"
  THING_EXISTS_RES=$(${UND_BIN} query ${TYPE} search --moniker="${MONIKER}" $(get_query_flags))
  THING_EXISTS=$(echo "${THING_EXISTS_RES}" | jq '.beacons | length')
  if [ "$THING_EXISTS" = "0" ]; then
    printf "[%s] [%s] Register %s for %s - %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TYPE}" "${ACC}" "$(get_addr ${ACC})"
    if [ "$TYPE" = "wrkchain" ]; then
      RES=$(${UND_BIN} tx wrkchain register --moniker "${MONIKER}" --genesis "${GEN_HASH}" --name "${MONIKER}" --base "geth" --from ${ACC} $(get_base_flags) --sequence ${ACC_SEQ})
      process_tx_log "${RES}"
    else
      RES=$(${UND_BIN} tx beacon register --moniker "${MONIKER}" --name "${MONIKER}" --from ${ACC} $(get_base_flags) --sequence ${ACC_SEQ})
      process_tx_log "${RES}"
    fi
    ACC_SEQUENCESS[$i]=$(awk "BEGIN {print $ACC_SEQ+1}")
  else
    printf "[%s] [%s] %s already registered\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TYPE}" "${MONIKER}"
  fi
done

printf "[%s] [%s] Done. Wait for approx. 2 blocks\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
sleep 12s

for i in ${!USER_ACCS[@]}
do
  ACC=${USER_ACCS[$i]}
  ACC_SEQUENCESS[$i]=$(get_curr_acc_sequence "${ACC}")
done

NOW_TIME=$(date +%s)
LAST_HEIGHT_CHECK=()
WC_B_IDS=()

for i in ${!USER_ACCS[@]}
do
  ACC=${USER_ACCS[$i]}
  TYPE=${TYPES[$i]}
  MONIKER="${TYPE}_${ACC}"
  WC_B_ID=$(${UND_BIN} query ${TYPE} search --moniker="${MONIKER}" $(get_query_flags) | jq -r ".${TYPE}s[0].${TYPE}_id")
  WC_B_IDS[$i]=$WC_B_ID
done

PRE_UP_PARAMS="0"
POST_UP_PARAMS="0"

while true
do
  check_online
  set_current_height
  set_und_bin

  if [ "$CURRENT_HEIGHT" = "$PRE_UPGRADE_CHECK_HEIGHT" ]; then
    if [ "$PRE_UP_PARAMS" = "0" ]; then
      Q_B_PARAMS=$(query_params "beacon" "${PRE_UPGRADE_CHECK_HEIGHT}")
      printf "[%s] [%s] beacon params at height %s (PRE UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PRE_UPGRADE_CHECK_HEIGHT}" "${Q_B_PARAMS}"
      Q_WC_PARAMS=$(query_params "wrkchain" "${PRE_UPGRADE_CHECK_HEIGHT}")
      printf "[%s] [%s] wrkchain params at height %s (PRE UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PRE_UPGRADE_CHECK_HEIGHT}" "${Q_WC_PARAMS}"
      Q_S_PARAMS=$(query_params "staking" "${PRE_UPGRADE_CHECK_HEIGHT}")
      printf "[%s] [%s] staking params at height %s (PRE UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PRE_UPGRADE_CHECK_HEIGHT}" "${Q_S_PARAMS}"
      PRE_UP_PARAMS="1"
    fi
  fi
  if [ "$CURRENT_HEIGHT" = "$UPGRADE_HEIGHT" ]; then
    if [ "$POST_UP_PARAMS" = "0" ]; then
      Q_B_PARAMS=$(query_params "beacon" "${UPGRADE_HEIGHT}")
      printf "[%s] [%s] beacon params at height %s (POST UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}" "${Q_B_PARAMS}"
      Q_WC_PARAMS=$(query_params "wrkchain" "${UPGRADE_HEIGHT}")
      printf "[%s] [%s] wrkchain params at height %s (POST UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}" "${Q_WC_PARAMS}"
      Q_S_PARAMS=$(query_params "staking" "${UPGRADE_HEIGHT}")
      printf "[%s] [%s] staking params at height %s (POST UPGRADE) = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}" "${Q_S_PARAMS}"
      POST_UP_PARAMS="1"
    fi
  fi

  LAST_HEIGHT=$(awk "BEGIN {print $CURRENT_HEIGHT-1}")
  for i in ${!USER_ACCS[@]}
  do
    check_online
    set_und_bin
    ACC=${USER_ACCS[$i]}
    ACC_SEQ=${ACC_SEQUENCESS[$i]}
    TYPE=${TYPES[$i]}
    MONIKER="${TYPE}_${ACC}"
    RES=""
    TX_HASH=""
    RAW_LOG=""
    TX_SUCCESS=""
    ID=${WC_B_IDS[$i]}
    if [ "$TYPE" = "wrkchain" ]; then
      WC_HASH="0x$(gen_hash)"
      WC_HEIGHT=${WC_HEIGHTS_BEACON_TIMESTAMPS[$i]}
      WC_HEIGHTS_BEACON_TIMESTAMPS[$i]=$(awk "BEGIN {print $WC_HEIGHT+1}")
      printf "[%s] [%s] %s record wrkchain block %s for %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" "${WC_HEIGHT}" "${MONIKER}"
      RES=$(${UND_BIN} tx wrkchain record ${ID} --wc_height ${WC_HEIGHT} --block_hash "${WC_HASH}" --from ${ACC} $(get_base_flags) --sequence ${ACC_SEQ})
      process_tx_log "${RES}"
      TX_SUCCESS=$(tx_success "${RES}")
    else
      B_HASH="$(gen_hash)"
      TS=${WC_HEIGHTS_BEACON_TIMESTAMPS[$i]}
      WC_HEIGHTS_BEACON_TIMESTAMPS[$i]=$(awk "BEGIN {print $TS+1}")
      printf "[%s] [%s] %s record beacon timestamp %s for %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" "${TS}" "${MONIKER}"
      RES=$(${UND_BIN} tx beacon record ${ID} --hash "$(gen_hash)" --subtime $(date +%s) --from ${ACC} $(get_base_flags) --sequence ${ACC_SEQ})
      process_tx_log "${RES}"
      TX_SUCCESS=$(tx_success "${RES}")
    fi

    update_acc_sequence "${TX_SUCCESS}" "${ACC}" "${i}" "${ACC_SEQ}"

    CHK=${LAST_HEIGHT_CHECK[$i]}
    UPGRADE_NOTE=""
    if [ "$CHK" != "$CURRENT_HEIGHT" ]; then
      if [ "$CURRENT_HEIGHT" = "$PRE_UPGRADE_CHECK_HEIGHT" ]; then
        UPGRADE_NOTE=" (PRE UPGRADE)"
      fi
      if [ "$CURRENT_HEIGHT" = "$UPGRADE_HEIGHT" ]; then
        UPGRADE_NOTE=" (POST UPGRADE)"
        SPNT_RES=$(query_spent_efund $(get_addr ${ACC}) "${CURRENT_HEIGHT}")
        printf "[%s] [%s] %s spent efund at height %s%s = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${ACC}" "${CURRENT_HEIGHT}" "${UPGRADE_NOTE}" "${SPNT_RES}"
      fi
      Q_RES=$(query_beacon_wrkchain "${TYPE}" "${ID}" "${CURRENT_HEIGHT}")
      printf "[%s] [%s] %s at height %s%s = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${MONIKER}" "${CURRENT_HEIGHT}" "${UPGRADE_NOTE}" "${Q_RES}"
      LAST_HEIGHT_CHECK[$i]=$CURRENT_HEIGHT
    fi

    if [ "$CURRENT_HEIGHT" = "$PURCHASE_STORAGE_HEIGHT" ]; then
      HAS_PURCHASED=${HAS_PURCHASED_STORAGE[$i]}
      if [ "$HAS_PURCHASED" = "0" ]; then
        ACC_SEQ=${ACC_SEQUENCESS[$i]}
        printf "[%s] [%s] purchase %s storage for %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${TYPE}" "${MONIKER}"
        RES=$(${UND_BIN} tx "${TYPE}" purchase_storage ${ID} "${STORAGE_PURCHASE}" --from ${ACC} $(get_base_flags) --sequence ${ACC_SEQ})
        process_tx_log "${RES}"
        TX_SUCCESS=$(tx_success "${RES}")
        update_acc_sequence "${TX_SUCCESS}" "${ACC}" "${i}" "${ACC_SEQ}"
        HAS_PURCHASED_STORAGE[$i]="1"
      fi
    fi
  done
  NOW_TIME=$(date +%s)
done
