#!/bin/bash

HERMES_LOG_FILE="/root/out/hermes.log"
CHANNEL_INITIALISED="/root/initialised"

if [ -f "$HERMES_LOG_FILE" ]; then
  rm "${HERMES_LOG_FILE}"
fi

touch "${HERMES_LOG_FILE}"

until nc -z "${FUND_RPC_IP}" "${FUND_GRPC_PORT}";
do
  echo "wait for FUND grpc port ${FUND_RPC_IP}:${FUND_GRPC_PORT}" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  sleep 1
done
until nc -z "${IBC_RPC_IP}" "${IBC_GRPC_PORT}";
do
  echo "wait for IBC grpc port ${IBC_RPC_IP}:${IBC_GRPC_PORT}" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  sleep 1
done


if [ ! -f "$CHANNEL_INITIALISED" ]; then
#  echo "wait for network to initialise" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))

  echo "wait 10s for networks to begin producing blocks" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  sleep 10
  echo "create IBC Channel" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  /usr/local/bin/hermes create channel --a-chain "${FUND_CHAIN_ID}" --b-chain "${IBC_CHAIN_ID}" --a-port transfer --b-port transfer --new-client-connection --yes &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  touch "${CHANNEL_INITIALISED}"
else
  echo "IBC Channel exists" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
fi
echo "starting hermes in 1s" &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
sleep 1s
/usr/local/bin/hermes start &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
