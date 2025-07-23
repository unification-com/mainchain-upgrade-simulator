#!/bin/bash

set -e

function generate_validator_stake() {
  local L_GENERATED_NETWORK_DIR="${1}"
  local L_NODE_NUM="${2}"
  local L_STAKE_DENOM="${3}"
  local L_USE_STAKE_OVERRIDES="${4}"

  local L_IS_SMALL
  L_IS_SMALL=$(awk "BEGIN {print $L_NODE_NUM%5}")

  local L_MONIKER="${PREFIX_NODE_VALIDATOR}${L_NODE_NUM}"
  local L_STAKE_INFO_FILE="${L_GENERATED_NETWORK_DIR}/stake_${L_MONIKER}.json"

  local L_COMM_VAL_NUM

  local L_COMMISSION_RATE="0.1"
  local L_COMMISSION_MAX_RATE="0.1"
  local L_COMMISSION_MAX_CHANGE_RATE="0.01"
  local L_NODE_STAKE="0"
  local L_MIN_SELF_DELEGATION="1"

  if [ "$CONF_VAL_STAKE_OVERRIDES" != "null" ] && [ "$L_USE_STAKE_OVERRIDES" = "yes" ]; then
    echo "process validator commission overrides"
    for row in $(echo "${CONF_VAL_STAKE_OVERRIDES}" | jq -r ".[] | @base64"); do
        L_COMM_VAL_NUM=$(_jq "${row}" '.validator')
        if [ "$L_COMM_VAL_NUM" = "$L_NODE_NUM" ]; then
          echo "override default commission for validator${L_NODE_NUM}"
          OVERRIDE_COMMISSION_RATE=$(_jq "${row}" '.rate')
          OVERRIDE_COMMISSION_MAX_RATE=$(_jq "${row}" '.max_rate')
          OVERRIDE_COMMISSION_MAX_CHANGE_RATE=$(_jq "${row}" '.max_change_rate')
          OVERRIDE_STAKE=$(_jq "${row}" '.stake')
          OVERRIDE_MIN_SELF_DELEGATION=$(_jq "${row}" '.min_self')
          if [ "$OVERRIDE_COMMISSION_RATE" != "null" ]; then
            echo "OVERRIDE_COMMISSION_RATE=${OVERRIDE_COMMISSION_RATE}"
            L_COMMISSION_RATE="${OVERRIDE_COMMISSION_RATE}"
          fi
          if [ "$OVERRIDE_COMMISSION_MAX_RATE" != "null" ]; then
            echo "OVERRIDE_COMMISSION_MAX_RATE=${OVERRIDE_COMMISSION_MAX_RATE}"
            L_COMMISSION_MAX_RATE="${OVERRIDE_COMMISSION_MAX_RATE}"
          fi
          if [ "$OVERRIDE_COMMISSION_MAX_CHANGE_RATE" != "null" ]; then
            echo "OVERRIDE_COMMISSION_MAX_CHANGE_RATE=${OVERRIDE_COMMISSION_MAX_CHANGE_RATE}"
            L_COMMISSION_MAX_CHANGE_RATE="${OVERRIDE_COMMISSION_MAX_CHANGE_RATE}"
          fi
          if [ "$OVERRIDE_STAKE" != "null" ]; then
            echo "OVERRIDE_STAKE=${OVERRIDE_STAKE}"
            L_NODE_STAKE="${OVERRIDE_STAKE}"
          fi
          if [ "$OVERRIDE_MIN_SELF_DELEGATION" != "null" ]; then
            echo "OVERRIDE_MIN_SELF_DELEGATION=${OVERRIDE_MIN_SELF_DELEGATION}"
            L_MIN_SELF_DELEGATION="${OVERRIDE_MIN_SELF_DELEGATION}"
          fi
        fi
    done
  fi

  if [ "$L_NODE_STAKE" = "0" ]; then
    if [ "$L_IS_SMALL" = "0" ]; then
      L_NODE_STAKE=$(perl -e "print int(rand($CONF_SMALL_MAX_STAKE-$CONF_SMALL_MIN_STAKE+1)) + $CONF_SMALL_MIN_STAKE")
#      L_NODE_STAKE=$(awk "BEGIN{srand();print int(rand()*($CONF_SMALL_MAX_STAKE-$CONF_SMALL_MIN_STAKE))+$CONF_SMALL_MIN_STAKE }")
      echo "${L_MONIKER} Small Stake = ${L_NODE_STAKE}"
    else
      L_NODE_STAKE=$(perl -e "print int(rand($CONF_MAX_STAKE-$CONF_MIN_STAKE+1)) + $CONF_MIN_STAKE")
#      L_NODE_STAKE=$(awk "BEGIN{srand();print int(rand()*($CONF_MAX_STAKE-$CONF_MIN_STAKE))+$CONF_MIN_STAKE }")
      echo "${L_MONIKER} Large Stake = ${L_NODE_STAKE}"
    fi
  fi

  cat >"${L_STAKE_INFO_FILE}" <<EOL
{
  "name": "${L_MONIKER}",
  "stake": "${L_NODE_STAKE}${L_STAKE_DENOM}",
  "commission_rate": "${L_COMMISSION_RATE}",
  "commission_max_rate": "${L_COMMISSION_MAX_RATE}",
  "commission_max_change_rate": "${L_COMMISSION_MAX_CHANGE_RATE}",
  "min_self_delegation": "${L_MIN_SELF_DELEGATION}"
}
EOL
}

function generate_gentx() {
  local L_BIN="${1}"
  local L_GLOBAL_HOME="${2}"
  local L_GENERATED_NETWORK_DIR="${3}"
  local L_NODE_NUM="${4}"

  local L_MONIKER="${PREFIX_NODE_VALIDATOR}${L_NODE_NUM}"
  local L_STAKE_INFO_FILE="${L_GENERATED_NETWORK_DIR}/stake_${L_MONIKER}.json"
  local L_NET_INFO_FILE="${L_GENERATED_NETWORK_DIR}/node_${L_MONIKER}.json"
  local L_GENTX_DIR="${L_GLOBAL_HOME}/config/gentx"

  local L_PUBKEY=""
  L_PUBKEY=$(get_pubkey_from_acc_name "${L_BIN}" "${L_GLOBAL_HOME}" "${L_MONIKER}"  | sed 's/"/\\"/g')

  mkdir -p "${L_GENTX_DIR}"

  ${L_BIN} genesis gentx "${L_MONIKER}" "$(cat < "${L_STAKE_INFO_FILE}" | jq -r '.stake')" \
                     --home "${L_GLOBAL_HOME}" \
                     --commission-rate "$(cat < "${L_STAKE_INFO_FILE}" | jq -r '.commission_rate')" \
                     --commission-max-rate "$(cat < "${L_STAKE_INFO_FILE}" | jq -r '.commission_max_rate')" \
                     --commission-max-change-rate "$(cat < "${L_STAKE_INFO_FILE}" | jq -r '.commission_max_change_rate')" \
                     --moniker "${L_MONIKER}" \
                     --details "${L_MONIKER}" \
                     --ip "$(cat < "${L_NET_INFO_FILE}" | jq -r '.ip')" \
                     --p2p-port "$(cat < "${L_NET_INFO_FILE}" | jq -r '.p2p_port')" \
                     --node-id "$(cat < "${L_NET_INFO_FILE}" | jq -r '.node_id')" \
                     --pubkey "$(cat < "${L_NET_INFO_FILE}" | jq -r '.val_pubkey_escaped')" \
                     --from "${L_MONIKER}" \
                     --keyring-backend test \
                     --output-document "${L_GENTX_DIR}/${L_MONIKER}.json"
}

function collect_gentxs() {
  local L_BIN="${1}"
  local L_GLOBAL_HOME="${2}"

  ${L_BIN} genesis collect-gentxs --home "${L_GLOBAL_HOME}"
}

function create_validator() {
  local L_BIN="${1}"
  local L_GLOBAL_HOME="${2}"
  local L_NODE_NUM="${3}"
  local L_MONIKER="${4}"
  local L_STAKE_DENOM="${5}"
  local L_WALLET_DIR="${6}"
  local L_GENERATED_NETWORK_DIR="${7}"
  local L_USE_STAKE_OVERRIDES="${8}"

  local L_COMMISSION_RATE="0.1"
  local L_COMMISSION_MAX_RATE="0.1"
  local L_COMMISSION_MAX_CHANGE_RATE="0.01"
  local L_NODE_STAKE="0"
  local L_MIN_SELF_DELEGATION="1"

  # generate stake
  generate_validator_stake "${L_GENERATED_NETWORK_DIR}" "${L_NODE_NUM}" "${L_STAKE_DENOM}" "${L_USE_STAKE_OVERRIDES}"
  # gentx
  generate_gentx "${L_BIN}" "${L_GLOBAL_HOME}" "${L_GENERATED_NETWORK_DIR}" "${L_NODE_NUM}"
}
