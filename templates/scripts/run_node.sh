#!/bin/bash

UND_LOG_FILE="/root/out/und.log"
RUN_WITH="/usr/local/bin/cosmovisor"

export DAEMON_NAME=und
export DAEMON_HOME="/root/.und_mainchain"
export DAEMON_RESTART_AFTER_UPGRADE=true
export DAEMON_RESTART_DELAY=5s

if [ -f "$UND_LOG_FILE" ]; then
  rm "${UND_LOG_FILE}"
fi

touch "${UND_LOG_FILE}"

${RUN_WITH} run start &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' > "${UND_LOG_FILE}"))
