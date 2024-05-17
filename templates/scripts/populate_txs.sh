#!/bin/bash

UND_BIN="/usr/local/bin/und_genesis"
UNDOLD_BIN="/usr/local/bin/und_genesis"
UNDNEW_BIN="/usr/local/bin/und_upgrade"
UPGRADE_HEIGHT=$1
DEVNET_RPC_IP=$2
DEVNET_RPC_PORT=$3
SCRIPT_ALIAS=$4
UPGRADE_PLAN_NAME=$5
CHAIN_ID=$6
DEVNET_RPC_TCP="tcp://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
DEVNET_RPC_HTTP="http://${DEVNET_RPC_IP}:${DEVNET_RPC_PORT}"
BROADCAST_MODE="sync"
GAS_PRICES="25.0nund"
UND_HOME="/root/.und_cli_txs"
PRE_DEFINED_TXS=$(cat /root/txs/pre_defined.json | jq)
HAS_PREDEFINED_GOV_TXS="null"
PROCESSED_GOV_TXS=()
if [ "$PRE_DEFINED_TXS" != "null" ]; then
  HAS_PREDEFINED_GOV_TXS=$(echo "${PRE_DEFINED_TXS}" | jq -r ".gov")
fi

NODE_ACCS=( __POP_TXS_NODE_ACCS__)
USER_ACCS=( __POP_TXS_TEST_ACCS__)
NODE_ACC_SEQUENCESS=( __POP_TXS_NODE_ACC_SEQUENCESS__)
USER_ACC_SEQUENCESS=( __POP_TXS_USER_ACC_SEQUENCESS__)

PROPOSALS_SUBMITTED=0
PRE_DEFINED_PROPOSALS_SUBMITTED=0
CURRENT_HEIGHT=0

cp -r "/root/.und_mainchain" "${UND_HOME}"

${UNDOLD_BIN} config chain-id "${CHAIN_ID}" --home "${UND_HOME}"
${UNDOLD_BIN} config node "${DEVNET_RPC_TCP}" --home "${UND_HOME}"

printf "[%s] [%s] UPGRADE_HEIGHT=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}"
printf "[%s] [%s] UPGRADE_PLAN_NAME=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_PLAN_NAME}"

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

function get_addr() {
  set_und_bin
  local ADDR
  ADDR=$(${UND_BIN} keys show $1 -a --keyring-backend test --keyring-dir ${UND_HOME})
  echo "${ADDR}"
}

function get_valoper_addr() {
  set_und_bin
  local ADDR
  ADDR=$(${UND_BIN} keys show $1 -a --bech val --keyring-backend test --keyring-dir ${UND_HOME})
  echo "${ADDR}"
}

function get_base_flags() {
#  local BROADCAST=${1:-$BROADCAST_MODE}
  local FLAGS="--broadcast-mode ${BROADCAST_MODE} --chain-id ${CHAIN_ID} --node ${DEVNET_RPC_TCP} --home ${UND_HOME} --output json --gas auto --gas-adjustment 1.5 --keyring-backend test --yes"
  echo "${FLAGS}"
}

function get_gas_flags() {
  local FLAGS="--gas-prices ${GAS_PRICES}"
  echo "${FLAGS}"
}

function get_query_flags() {
  local FLAGS="--node ${DEVNET_RPC_TCP} --chain-id ${CHAIN_ID} --output json --home ${UND_HOME}"
  echo "${FLAGS}"
}

check_accounts_exist() {
  set_und_bin
  if { ${UND_BIN} keys show --keyring-dir=${UND_HOME} --keyring-backend=test $1 2>&1 >&3 3>&- | grep '^' >&2; } 3>&1; then
    echo "${1} does not seem to exist in keyring. Exiting"
    exit 1
  else
    printf "[%s] [%s] Found %s in keyring\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${1}"
  fi
}

function get_curr_acc_sequence() {
  set_und_bin
  local ACC=$1
  local RES=$(${UND_BIN} query account $(get_addr "${ACC}") --node=${DEVNET_RPC_TCP} --chain-id=${CHAIN_ID} --output=json)
  local CURR=$(echo "${RES}" | jq --raw-output '.sequence')
  local CURR_INT=$(awk "BEGIN {print $CURR}")
  echo "${CURR_INT}"
}

function update_node_acc_sequences() {
  printf "[%s] [%s] update node acc sequences\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  for i in ${!NODE_ACCS[@]}
  do
    NODE_ACC_SEQUENCESS[$i]=$(get_curr_acc_sequence "${NODE_ACCS[$i]}")
  done
}

function update_user_acc_sequences() {
  printf "[%s] [%s] update user acc sequences\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  for i in ${!USER_ACCS[@]}
  do
    USER_ACC_SEQUENCESS[$i]=$(get_curr_acc_sequence "${USER_ACCS[$i]}")
  done
}

function update_all_acc_sequences() {
  update_user_acc_sequences
  update_node_acc_sequences
}

function process_tx_log() {
  local LOG_C=${1}

  printf "[%s] [%s] TX LOG:\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  for line in $LOG_C
  do
    printf "[%s] [%s] %s:\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${line}"
  done

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

function send_fund() {
  set_und_bin
  printf "[%s] [%s] SEND TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  for i in ${!USER_ACCS[@]}
  do
    TO_ACC=${USER_ACCS[$RANDOM % ${#USER_ACCS[@]}]}
    FROM_ACC=${USER_ACCS[$i]}

    FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[$i]}
    RND_AMOUNT=$(head -200 /dev/urandom | cksum | cut -f1 -d " ")
    AMOUNT="${RND_AMOUNT}00nund"
    if [ "$FROM_ACC" != "$TO_ACC" ]; then
      printf "[%s] [%s] send %s from %s to %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${AMOUNT}" "${FROM_ACC}" "${TO_ACC}"
      RES=$(${UND_BIN} tx bank send ${FROM_ACC} $(get_addr ${TO_ACC}) ${AMOUNT} $(get_base_flags) $(get_gas_flags) --sequence "${FROM_ACC_SEQ}")
      process_tx_log "${RES}"
    fi
  done
}

function stake_fund() {
  set_und_bin
  printf "[%s] [%s] STAKE TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  for i in ${!USER_ACCS[@]}
  do
    NODE_ACC=${NODE_ACCS[$RANDOM % ${#NODE_ACCS[@]}]}
    NODE_VALOPER=$(get_valoper_addr ${NODE_ACC})
    FROM_ACC=${USER_ACCS[$i]}
    FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[$i]}
    RND_AMOUNT=$(head -200 /dev/urandom | cksum | cut -f1 -d " ")
    AMOUNT="${RND_AMOUNT}0nund"
    printf "[%s] [%s] %s stake %s to %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${FROM_ACC}" "${AMOUNT}" "${NODE_ACC}"
    RES=$(${UND_BIN} tx staking delegate ${NODE_VALOPER} ${AMOUNT} --from ${FROM_ACC} $(get_base_flags) $(get_gas_flags) --sequence "${FROM_ACC_SEQ}")
    process_tx_log "${RES}"
  done
}

function should_unstake() {
  # 30% chance of unstake
  if (( RANDOM % 7 )); then
    echo "0"
  else
    echo "1"
  fi
}

function unstake_fund() {
  set_und_bin
  printf "[%s] [%s] UNSTAKE TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  for i in ${!USER_ACCS[@]}
  do
    NODE_ACC=${NODE_ACCS[$RANDOM % ${#NODE_ACCS[@]}]}
    NODE_VALOPER=$(get_valoper_addr ${NODE_ACC})

    SHOULD_DO_UNSTAKE=$(should_unstake)
    if [ "$SHOULD_DO_UNSTAKE" = "1" ]; then
      FROM_ACC=${USER_ACCS[$i]}
      FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[$i]}
      RND_AMOUNT=$(head -200 /dev/urandom | cksum | cut -f1 -d " ")
      AMOUNT="${RND_AMOUNT}nund"
      printf "[%s] [%s] %s unstake %s from %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${FROM_ACC}" "${AMOUNT}" "${NODE_ACC}"
      RES=$(${UND_BIN} tx staking unbond ${NODE_VALOPER} ${AMOUNT} --from ${FROM_ACC} $(get_base_flags) $(get_gas_flags) --sequence "${FROM_ACC_SEQ}")
      process_tx_log "${RES}"
    fi
  done

}

function submit_gov_proposals() {
  set_und_bin

  local PROPOSAL_CMD="submit-proposal"
  if [ "$CURRENT_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    PROPOSAL_CMD="submit-legacy-proposal"
  fi

  printf "[%s] [%s] GOV SUBMIT TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  local RND=$RANDOM % ${#USER_ACCS[@]}
  FROM_ACC=${USER_ACCS[RND]}
  FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[$RND]}
  PROPOSAL_TITLE="${FROM_ACC} Proposal"
  PROPOSAL_TEXT="Propose to do this - $(gen_hash)"
  DEPOSIT="10000000000nund"
  printf "[%s] [%s] %s submit proposal %s: %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${FROM_ACC}" "${PROPOSAL_TITLE}" "${PROPOSAL_TEXT}"
  RES=$(${UND_BIN} tx gov ${PROPOSAL_CMD} \
    --title "${PROPOSAL_TITLE}" \
    --description "${PROPOSAL_TEXT}" \
    --type "Text" \
    --deposit "${DEPOSIT}" \
    --from ${FROM_ACC} \
    $(get_base_flags) \
    $(get_gas_flags) \
    --sequence "${FROM_ACC_SEQ}")
  process_tx_log "${RES}"
  PROPOSALS_SUBMITTED=1
}

function submit_upgrade_gov_proposals() {
  set_und_bin
  printf "[%s] [%s] GOV SUBMIT UPGRADE TX\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

  FROM_ACC=${USER_ACCS[0]}
  FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[0]}
  PROPOSAL_TITLE="upgrade ${UPGRADE_PLAN_NAME}"
  PROPOSAL_TEXT="Propose to upgrade to ${UPGRADE_PLAN_NAME}"
  DEPOSIT="10000000000nund"
  printf "[%s] [%s] %s submit upgrade proposal %s: %s (%s at height %s)\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${FROM_ACC}" "${PROPOSAL_TITLE}" "${PROPOSAL_TEXT}" "${UPGRADE_PLAN_NAME}" "${UPGRADE_HEIGHT}"

  RES=$(${UND_BIN} tx gov submit-legacy-proposal software-upgrade "${UPGRADE_PLAN_NAME}" \
    --title "${PROPOSAL_TITLE}" \
    --description "${PROPOSAL_TEXT}" \
    --upgrade-height "${UPGRADE_HEIGHT}" \
    --upgrade-info "https://github.com/unification-com/mainchain/tree/percival" \
    --no-validate \
    --deposit "${DEPOSIT}" \
    --from ${FROM_ACC} \
    $(get_base_flags) \
    $(get_gas_flags) \
    --sequence "${FROM_ACC_SEQ}")
  process_tx_log "${RES}"
  PROPOSALS_SUBMITTED=1
}

function get_vote() {
  if (( RANDOM % 6 )); then
    echo "yes"
  else
    echo "no"
  fi
}

function send_vote_tx() {
  set_und_bin
  local ID=${1}
  local FROM=${2}
  local FORCE=${3}
  local VOTE=$(get_vote)

  if [ "$FORCE" = "yes" ]; then
    VOTE="${FORCE}"
  elif [ "$FORCE" = "no" ]; then
    VOTE="${FORCE}"
  fi

  printf "[%s] [%s] %s votes %s on %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${NODE_ACC}" "${VOTE}" "${PROP_ID}"
  RES=$(${UND_BIN} tx gov vote ${ID} ${VOTE} --from ${FROM} $(get_base_flags) $(get_gas_flags))
  process_tx_log "${RES}"
}

function vote_gov_proposals() {
  set_und_bin
  local FORCE=${1}
  local STATUS_QUERY_TEXT="PROPOSAL_STATUS_VOTING_PERIOD"
  local PROP_ID_KEY="id"
  #if [ "$CURRENT_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
  #  STATUS_QUERY_TEXT="voting_period"
  #  PROP_ID_KEY="id"
  #fi

  printf "[%s] [%s] GOV VOTE TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  local PROPOSALS=$(${UND_BIN} query gov proposals $(get_query_flags) "--status" "${STATUS_QUERY_TEXT}")
  for row in $(echo "${PROPOSALS}" | jq -r ".proposals[] | @base64"); do
    update_all_acc_sequences
    PROP_ID=$(_jq ${row} ".${PROP_ID_KEY}")
    for i in ${!NODE_ACCS[@]}
    do
      send_vote_tx "${PROP_ID}" "${NODE_ACCS[$i]}" "${FORCE}"
    done
    for j in ${!USER_ACCS[@]}
    do
      send_vote_tx "${PROP_ID}" "${USER_ACCS[$j]}" "${FORCE}"
    done
  done
}

function withdraw_rewards() {
  set_und_bin
  printf "[%s] [%s] WITHDRAW REWARDS TXs\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
  for i in ${!NODE_ACCS[@]}
  do
    NODE_ACC=${NODE_ACCS[$i]}
    NODE_VALOPER=$(get_valoper_addr ${NODE_ACC})
    printf "[%s] [%s] %s withdrawing from self\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${NODE_ACC}"
    RES=$(${UND_BIN} tx distribution withdraw-rewards ${NODE_VALOPER} --commission --from ${NODE_ACC} $(get_base_flags) $(get_gas_flags))
    process_tx_log "${RES}"

    for j in ${!USER_ACCS[@]}
    do
      USER_ACC=${USER_ACCS[$j]}
      printf "[%s] [%s] %s withdrawing from %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${USER_ACC}" "${NODE_ACC}"
      RES=$(${UND_BIN} tx distribution withdraw-rewards ${NODE_VALOPER} --from ${USER_ACC} $(get_base_flags) $(get_gas_flags))
      process_tx_log "${RES}"
    done
    update_user_acc_sequences
  done
}

function pre_defined_gov_tx_was_sent() {
  local PD_GOV_TX_ID=${1}
  local WAS_SENT
  if [[ ${PROCESSED_GOV_TXS[@]} =~ "$PD_GOV_TX_ID" ]]; then
    WAS_SENT="1"
  else
    WAS_SENT="0"
  fi
  echo "${WAS_SENT}"
}

function do_send_pre_defined_gov_tx() {
  local PD_GOV_TX_ID=${1}
  local PD_GOV_TX_SUB_HEIGHT=${2}
  local AT_SUB_HEIGHT="0"
  local SEND="0"
  local WAS_SENT
  WAS_SENT=$(pre_defined_gov_tx_was_sent "${PD_GOV_TX_ID}")
  if [ "$PD_GOV_TX_SUB_HEIGHT" -le "$CURRENT_HEIGHT" ] && [ "$WAS_SENT" = "0" ]; then
    SEND="1"
  fi
  echo "${SEND}"
}

function process_pre_defined_gov_txs() {
  printf "[%s] [%s] process pre-defined gov txs (PRE_DEFINED_PROPOSALS_SUBMITTED = %s)\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PRE_DEFINED_PROPOSALS_SUBMITTED}"
  local PD_GOV_TX_ID
  local PD_GOV_TX_TITLE
  local PD_GOV_TX_PROP_TYPE
  local PD_GOV_TX_SUB_HEIGHT
  local PD_GOV_TX_JSON_FILE
  local PD_GOV_SEND
  local RES
  local FROM_ACC=${USER_ACCS[0]}
  local FROM_ACC_SEQ=${USER_ACC_SEQUENCESS[0]}
  local PROPOSAL_CMD="submit-proposal"
  if [ "$CURRENT_HEIGHT" -ge "$UPGRADE_HEIGHT" ]; then
    PROPOSAL_CMD="submit-legacy-proposal"
  fi
  for row in $(echo "${PRE_DEFINED_TXS}" | jq -r ".gov[] | @base64"); do
    if [ "$PRE_DEFINED_PROPOSALS_SUBMITTED" = "0" ]; then
      PD_GOV_TX_ID=$(_jq "${row}" '.id')
      PD_GOV_TX_TITLE=$(_jq "${row}" '.title')
      PD_GOV_TX_PROP_TYPE=$(_jq "${row}" '.type')
      PD_GOV_TX_SUB_HEIGHT=$(_jq "${row}" '.submit_height')
      PD_GOV_TX_JSON_FILE="/root/txs/gov.${PD_GOV_TX_ID}.json"
      PD_GOV_SEND=$(do_send_pre_defined_gov_tx "${PD_GOV_TX_ID}" "${PD_GOV_TX_SUB_HEIGHT}")
      printf "[%s] [%s] Check pre-defined gov proposal ID %s. Send height = %s, Current height = %s. Send? = %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PD_GOV_TX_ID}" "${PD_GOV_TX_SUB_HEIGHT}" "${CURRENT_HEIGHT}" "${PD_GOV_SEND}"
      if [ "$PD_GOV_SEND" = "1" ]; then
        printf "[%s] [%s] Submit pre-defined gov proposal ID %s - %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${PD_GOV_TX_ID}" "${PD_GOV_TX_TITLE}"

        if [ "$PD_GOV_TX_PROP_TYPE" = "param_change" ]; then
          RES=$(${UND_BIN} tx gov ${PROPOSAL_CMD} param-change \
            "${PD_GOV_TX_JSON_FILE}" \
            --from ${FROM_ACC} \
            $(get_base_flags) \
            $(get_gas_flags) \
            --sequence "${FROM_ACC_SEQ}")
        fi
        process_tx_log "${RES}"
        PRE_DEFINED_PROPOSALS_SUBMITTED=1
        PROCESSED_GOV_TXS+=("${PD_GOV_TX_ID}")
      fi
    fi
  done
}

function process_pre_defined_txs() {
  if [ "$PRE_DEFINED_TXS" != "null" ]; then
    if [ "$HAS_PREDEFINED_GOV_TXS" != "null" ]; then
      sleep 7s
      update_all_acc_sequences
      process_pre_defined_gov_txs
      if [ "$PRE_DEFINED_PROPOSALS_SUBMITTED" = "1" ]; then
        sleep 7s
        update_all_acc_sequences
        printf "[%s] [%s] Vote YES for pre-defined gov proposal\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
        sleep 7s
        vote_gov_proposals "yes"
        PRE_DEFINED_PROPOSALS_SUBMITTED=0
      fi
    fi
  fi
}

for i in ${!USER_ACCS[@]}
do
  check_accounts_exist "${USER_ACCS[$i]}"
done

for i in ${!NODE_ACCS[@]}
do
  check_accounts_exist "${NODE_ACCS[$i]}"
done

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
printf "[%s] [%s] Running transactions\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"

START_TIME=$(date +%s)

update_all_acc_sequences

# submit upgrade proposal
printf "[%s] [%s] Send Upgrade proposal for height %s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${UPGRADE_HEIGHT}"
submit_upgrade_gov_proposals
sleep 6s
update_all_acc_sequences
printf "[%s] [%s] Vote YES for upgrade\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
vote_gov_proposals "yes"

while true
do
  sleep 6s
  check_online
  set_current_height
  set_und_bin
  update_all_acc_sequences

  # prioritise pre-defined txs
  process_pre_defined_txs

  # send some FUND
  send_fund
  sleep 6s
  update_all_acc_sequences

  # stakes
  stake_fund
  sleep 6s
  update_all_acc_sequences

  if [ "$PROPOSALS_SUBMITTED" = "0" ]; then
    # submit gov proposals
    submit_gov_proposals
    sleep 6s
    update_all_acc_sequences

    # vote gov proposals
    vote_gov_proposals
    sleep 6s
    update_all_acc_sequences
  fi

  DO_GOV=$(awk "BEGIN{srand();print int(rand()*(5-1))+1 }")
  printf "[%s] [%s] DO_GOV=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DO_GOV}"
  if [ $DO_GOV -gt 3 ] && [ "$PRE_DEFINED_PROPOSALS_SUBMITTED" = "0" ]; then
    printf "[%s] [%s] Set PROPOSALS_SUBMITTED=0\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
    # next loop, submit a proposal
    PROPOSALS_SUBMITTED=0
  fi

  # withdraw rewards
  if [ "$CURRENT_HEIGHT" -ge "20" ]; then
    DO_WITHDRAW=$(awk "BEGIN{srand();print int(rand()*(10-1))+1 }")
    printf "[%s] [%s] DO_WITHDRAW=%s\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')" "${DO_WITHDRAW}"
    if [ $DO_WITHDRAW -gt 8 ]; then
      withdraw_rewards
      sleep 6s
      update_all_acc_sequences
    fi

    # unstake
    unstake_fund
    sleep 6s
    update_all_acc_sequences
  fi

  # send some FUND
  send_fund
  sleep 6s
  update_all_acc_sequences
done

printf "[%s] [%s] Finished transactions\n" "${SCRIPT_ALIAS}" "$(date +'%Y-%m-%d %H:%M:%S.%3N')"
