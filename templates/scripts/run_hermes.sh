#!/bin/bash

HERMES_LOG_FILE="/root/out/hermes.log"
CHANNEL_INITIALISED="/root/initialised"

FUND_CHAIN_ID=${1}
IBC_CHAIN_ID=${2}

if [ -f "$HERMES_LOG_FILE" ]; then
  rm "${HERMES_LOG_FILE}"
fi

touch "${HERMES_LOG_FILE}"

if [ ! -f "$CHANNEL_INITIALISED" ]; then
  echo "wait for network to initialise"
  sleep 10s
  echo "create IBC Channel"
  /usr/local/bin/hermes create channel --a-chain "${FUND_CHAIN_ID}" --b-chain "${IBC_CHAIN_ID}" --a-port transfer --b-port transfer --new-client-connection --yes &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
  touch "${CHANNEL_INITIALISED}"
else
  echo "IBC Channel exists"
fi
echo "starting hermes in 10s"
sleep 10s
/usr/local/bin/hermes start &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> "${HERMES_LOG_FILE}"))
