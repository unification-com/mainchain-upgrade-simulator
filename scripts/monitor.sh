#!/bin/bash

set -e

# Get some config values
CONFIG="./config.json"
GENESIS_VER=$(cat < "${CONFIG}" | jq -r ".apps.und.genesis.version")
UPGRADE_VER=$(cat < "${CONFIG}" | jq -r ".apps.und.upgrade.branch")
UPGRADE_HEIGHT=$(cat < "${CONFIG}" | jq -r ".apps.und.upgrade.upgrade_height")
UPGRADE_PLAN=$(cat < "${CONFIG}" | jq -r ".apps.und.upgrade.upgrade_plan_name")
NUM_VALIDATORS=$(cat < "${CONFIG}" | jq -r ".apps.und.nodes.num_validators")
NUM_SENTRIES=$(cat < "${CONFIG}" | jq -r ".apps.und.nodes.num_sentries")
NUM_SEEDS=$(cat < "${CONFIG}" | jq -r ".apps.und.nodes.num_seeds")
NUM_RPCS=$(cat < "${CONFIG}" | jq -r ".apps.und.nodes.num_rpcs")
CONTAINER_PREFIX=$(cat < "${CONFIG}" | jq -r ".docker.container_prefix")

IGNORE_TOT_SUPPLY_HEIGHT=$(awk "BEGIN {print $UPGRADE_HEIGHT-1}")

# in DevNet, this will always be derived from "transfer/channel-0/nund"
# See https://tutorials.cosmos.network/tutorials/6-ibc-dev/#how-are-ibc-denoms-derived
IBC_DENOM="ibc/D6CFF2B192E06AFD4CD78859EA7CAD8B82405959834282BE87ABB6B957939618"

# Result formatting
R_DIV="=============================="
R_DIV="${R_DIV}${R_DIV}${R_DIV}"
R_HEADER="\n %-20s | %10s | %10s | %10s\n"
R_FORMAT=" %-20s | %10s | %10s | %10s\n"
R_WIDTH=60

# Regex to strip log formatting
STRIP_FMT_REGEX="\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]"

# Vars
DOCKER_CONTAINERS=()
HEIGHTS=()
UPGRADED=()
UPGRADE_TIME=()

TOTAL_NODES=$(awk "BEGIN {print $NUM_VALIDATORS+$NUM_SENTRIES+$NUM_SEEDS+$NUM_RPCS}")
NUM_NODES_UP=${#DOCKER_CONTAINERS[@]}
TOTAL_VALID_TXS=0
TOTAL_INVALID_TXS=0
LAST_HEIGHT=0
LAST_VALID_TXS=0
LAST_INVALID_TXS=0
SUCCESSFUL_UPGRADES=0
TOTAL_SUPPLY=0
TOTAL_LOCKED_EFUND=0
TOTAL_SPENT_EFUND=0
TOTAL_IBC_SUPPLY=0

function check_docker() {
  local RES
  RES=$(docker compose ps 2>&1)
  if [ "$RES" = "no configuration file provided: not found" ]; then
    echo 0
  else
    echo 1
  fi
}

function get_containers() {
  DOCKER_CONTAINERS=()
  NODES=()
  HEIGHTS=()
  UPGRADED=()
  local D
  D=$(check_docker)

  if [ "$D" = "1" ]; then
    for row in $(docker compose ps --format json | jq -sc '.[] | if type=="array" then .[] else . end' | jq -s | jq -r '.[] | @base64'); do
      _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
      }
      C_NAME=$(_jq '.Name')
      if [[ "$C_NAME" =~ ^"${CONTAINER_PREFIX}fund_" ]]; then
        DOCKER_CONTAINERS+=( "${C_NAME}" )
        UPGRADED+=( "no" )
        HEIGHTS+=( "0" )
        UPGRADE_TIME+=( "-" )
      fi
    done
  fi

  NUM_NODES_UP=${#DOCKER_CONTAINERS[@]}
}

function get_from_logs() {
  local TMP
  local RESULT
  local CONTAINER="${1}"
  local NUM_LINES="${2}"
  local TO_GREP="${3}"
  local TO_GET="${4}"

  if [ "$NUM_LINES" = "0" ]; then
    NUM_LINES="100"
  fi

  TMP=$(docker logs -n "${NUM_LINES}" "${CONTAINER}" | sed -r "s/${STRIP_FMT_REGEX}//g" | grep "${TO_GREP}" | tail -1)

  if [ ! "$TMP" = "" ]; then
    RESULT=$(echo "${TMP}" | sed "s/${TO_GET}/\1/")
  fi

  echo "${RESULT}"
}

function read_node_logs() {
  for i in "${!DOCKER_CONTAINERS[@]}"
  do
    LH=$(get_from_logs "${DOCKER_CONTAINERS[$i]}" "100" "committed state" ".*height=\(.*\) module=.*")

    if [ ! "$LH" = "" ]; then
      HEIGHTS[$i]=${LH}

      if [ "${UPGRADED[$i]}" = "no" ]; then
        if [ "$LH" -ge "$UPGRADE_HEIGHT" ]; then
          UP_T=$(get_from_logs "${DOCKER_CONTAINERS[$i]}" "1000" "applying upgrade" "\(.*\) INF.*")
          if [ "$UP_T" != "" ]; then
            UPGRADED[$i]="yes"
            UPGRADE_TIME[$i]="${UP_T}"
            SUCCESSFUL_UPGRADES=$(awk "BEGIN {print $SUCCESSFUL_UPGRADES+1}")
          fi
        fi
      fi
    fi
  done
}

function get_total_txs() {
  local V_TXS
  local INV_TXS
  if [ "${HEIGHTS[0]}" -gt "$LAST_HEIGHT" ]; then
    LAST_HEIGHT="${HEIGHTS[0]}"
    V_TXS=$(get_from_logs "${DOCKER_CONTAINERS[0]}" "100" "executed block height=${HEIGHTS[0]}" ".*num_valid_txs=\(.*\).*")
    INV_TXS=$(get_from_logs "${DOCKER_CONTAINERS[0]}" "100" "executed block height=${HEIGHTS[0]}" ".*num_invalid_txs=\(.*\) num_valid_txs.*")
    LAST_VALID_TXS="${V_TXS}"
    LAST_INVALID_TXS="${INV_TXS}"
    TOTAL_VALID_TXS=$(awk "BEGIN {print $TOTAL_VALID_TXS+$V_TXS}")
    TOTAL_INVALID_TXS=$(awk "BEGIN {print $TOTAL_INVALID_TXS+$INV_TXS}")
  fi
}

function get_total_supply() {
  local TOT_S

  if [ "$LAST_HEIGHT" -gt "0" ] && [ "$LAST_HEIGHT" != "$IGNORE_TOT_SUPPLY_HEIGHT" ] && [ "$LAST_HEIGHT" != "$UPGRADE_HEIGHT" ]; then
    TOT_S=$(curl -s http://localhost:1320/mainchain/enterprise/v1/supply/nund | jq -r '.amount.amount')
    if [ "$TOT_S" -gt "0" ]; then
      TOTAL_SUPPLY=$(echo "${TOT_S}" | awk '{printf("%.2f", $1/(1000000000))}')
    fi
  fi
}

function get_locked_efund() {
  local TOTAL_L
  if [ "$LAST_HEIGHT" -gt "0" ] && [ "$LAST_HEIGHT" != "$IGNORE_TOT_SUPPLY_HEIGHT" ] && [ "$LAST_HEIGHT" != "$UPGRADE_HEIGHT" ]; then
    TOTAL_L=$(curl -s http://localhost:1320/mainchain/enterprise/v1/locked | jq -r '.amount.amount')
    if [ "$TOTAL_L" -gt "0" ]; then
      TOTAL_LOCKED_EFUND=$(echo "${TOTAL_L}" | awk '{printf("%.2f", $1/(1000000000))}')
    fi
  fi
}

function get_spent_efund() {
  local TOTAL_SP
  if [ "$LAST_HEIGHT" -gt "0" ] && [ "$LAST_HEIGHT" != "$IGNORE_TOT_SUPPLY_HEIGHT" ] && [ "$LAST_HEIGHT" != "$UPGRADE_HEIGHT" ]; then
    TOTAL_SP=$(curl -s http://localhost:1320/mainchain/enterprise/v1/total_spent | jq -r '.amount.amount')
    if [ "$TOTAL_SP" -gt "0" ]; then
      TOTAL_SPENT_EFUND=$(echo "${TOTAL_SP}" | awk '{printf("%.2f", $1/(1000000000))}')
    fi
  fi
}

function get_ibc_supply() {
  local TOT_IBC
  local DENOM
  local AMNT=0
  TOT_IBC=$(curl -s http://localhost:27002/cosmos/bank/v1beta1/supply | jq -r '.supply[0]')
  DENOM=$(echo "${TOT_IBC}" | jq -r ".denom")

  if [ "$DENOM" = "$IBC_DENOM" ]; then
    AMNT=$(echo "${TOT_IBC}" | jq -r ".amount")
  fi
  if [ "$AMNT" -gt "0" ]; then
    TOTAL_IBC_SUPPLY=$(echo "${AMNT}" | awk '{printf("%.2f", $1/(1000000000))}')
  fi
}

function print_info() {
  printf "\nUpgrading    : %s -> %s\n" "${GENESIS_VER}" "${UPGRADE_VER}"
  printf "Upgrade Plan : %s, height=%s\n" "${UPGRADE_PLAN}"  "${UPGRADE_HEIGHT}"
  printf "FUND Nodes   : %s (%s Validators)\n" "${TOTAL_NODES}" "${NUM_VALIDATORS}"
}

function print_results() {
  print_info

  printf "${R_HEADER}" "CONTAINER" "HEIGHT" "UPGRADED" "UPGR. TIME"

  printf "%${R_WIDTH}.${R_WIDTH}s\n" "${R_DIV}"

  for i in "${!DOCKER_CONTAINERS[@]}"
  do
    printf "${R_FORMAT}" "${DOCKER_CONTAINERS[$i]}" "${HEIGHTS[$i]}" "${UPGRADED[$i]}" "${UPGRADE_TIME[$i]}"
  done

  printf "${R_FORMAT}" "" "" "${SUCCESSFUL_UPGRADES} / ${TOTAL_NODES}"

  printf "\nValid txs last block  : %s\n" "${LAST_VALID_TXS}"
  printf "Inalid txs last block : %s\n" "${LAST_INVALID_TXS}"
  printf "Total Valid Txs       : %s\n" "${TOTAL_VALID_TXS}"
  printf "Total Invalid Txs     : %s\n\n" "${TOTAL_INVALID_TXS}"

  printf "Total Locked eFUND    : %'.2f\n" "${TOTAL_LOCKED_EFUND}"
  printf "Total Spent eFUND     : %'.2f\n" "${TOTAL_SPENT_EFUND}"
  printf "Total Supply          : %'.2f\n\n" "${TOTAL_SUPPLY}"

  printf "Total on IBC Chain    : %'.2f\n" "${TOTAL_IBC_SUPPLY}"
}

function setup() {
  while [ "$NUM_NODES_UP" -lt "$TOTAL_NODES" ];
  do
    sleep 0.5
    get_containers
    clear
    print_info
    printf "\nWaiting for containers to start...\n"
    printf "\nUp: %s / %s\n" "${NUM_NODES_UP}" "${TOTAL_NODES}"
  done
}

function monitor() {
  while true; do
    read_node_logs
    get_total_txs
    get_total_supply
    get_locked_efund
    get_spent_efund
    get_ibc_supply
    clear
    print_results
    sleep 1
  done
}

# Run
setup
monitor
