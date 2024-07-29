#!/bin/bash

GAIAD_LOG_FILE="/root/out/gaiad.log"

if [ -f "$GAIAD_LOG_FILE" ]; then
  rm "${GAIAD_LOG_FILE}"
fi

touch "${GAIAD_LOG_FILE}"

/usr/local/bin/gaiad start --home /root/.simapp &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' > "${GAIAD_LOG_FILE}"))
