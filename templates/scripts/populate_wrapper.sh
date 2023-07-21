#!/bin/bash

POPULATE_LOG_FILE="/root/out/populate.log"
BEACON_WRKCHAIN_ALIAS="beac_wrk"
TXS_ALIAS="txs"
IBC_ALIAS="ibc"

BEACON_WRKCHAIN_LOG="/root/out/populate_${BEACON_WRKCHAIN_ALIAS}.log"
TXS_LOG="/root/out/populate_${TXS_ALIAS}.log"
IBC_LOG="/root/out/populate_${IBC_ALIAS}.log"

# $1 = upgrade height
# $2 = RPC IP
# $3 = RPC port
# $4 = num storage slots to purchase after upgrade (beacons/wrkchains)
# $5 = upgrade plan name (tx runner)
# $6 = IBC Simd RPC
# $7 = Chain ID
# $8 = IBC Chain ID

UPGRADE_HEIGHT=${1}
DEVNET_RPC_IP=${2}
DEVNET_RPC_PORT=${3}
STORAGE_PURCHASE=${4}
UPGRADE_PLAN_NAME=${5}
IBC_RPC=${6}
CHAIN_ID=${7}
IBC_CHAIN_ID=${8}

if [ -f "$POPULATE_LOG_FILE" ]; then
  rm "${POPULATE_LOG_FILE}"
fi

if [ -f "$BEACON_WRKCHAIN_LOG" ]; then
  rm "${BEACON_WRKCHAIN_LOG}"
fi

if [ -f "$TXS_LOG" ]; then
  rm "${TXS_LOG}"
fi

if [ -f "$IBC_LOG" ]; then
  rm "${IBC_LOG}"
fi

touch "${POPULATE_LOG_FILE}"
touch "${BEACON_WRKCHAIN_LOG}"
touch "${TXS_LOG}"
touch "${IBC_LOG}"

set -m

/root/scripts/populate_beacons_wrkchains.sh "${UPGRADE_HEIGHT}" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}" "${BEACON_WRKCHAIN_ALIAS}" "${STORAGE_PURCHASE}" "${CHAIN_ID}" >> "${POPULATE_LOG_FILE}" 2>&1 &
/root/scripts/populate_txs.sh "${UPGRADE_HEIGHT}" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}" "${TXS_ALIAS}" "${UPGRADE_PLAN_NAME}" "${CHAIN_ID}" >> "${POPULATE_LOG_FILE}" 2>&1 &
/root/scripts/populate_ibc.sh "${UPGRADE_HEIGHT}" "${DEVNET_RPC_IP}" "${DEVNET_RPC_PORT}" "${IBC_ALIAS}" "${UPGRADE_PLAN_NAME}" "${IBC_RPC}" "${CHAIN_ID}" "${IBC_CHAIN_ID}" >> "${POPULATE_LOG_FILE}" 2>&1 &

tail -n 3 -f "${POPULATE_LOG_FILE}" | grep --line-buffered '.*' | while read -r LINE0
do
    echo "${LINE0}";
    echo "${LINE0}" | grep -oP '^\['"${BEACON_WRKCHAIN_ALIAS}"'\].*+' | sed 's/\['"${BEACON_WRKCHAIN_ALIAS}"'\] //' >> "${BEACON_WRKCHAIN_LOG}";
    echo "${LINE0}" | grep -oP '^\['"${TXS_ALIAS}"'\].*+' | sed 's/\['"${TXS_ALIAS}"'\] //' >> "${TXS_LOG}";
    echo "${LINE0}" | grep -oP '^\['"${IBC_ALIAS}"'\].*+' | sed 's/\['"${IBC_ALIAS}"'\] //' >> "${IBC_LOG}";
done
