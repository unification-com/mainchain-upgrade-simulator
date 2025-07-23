#!/bin/bash

UND_LOG_FILE="/root/out/und.log"
RUN_WITH="/usr/local/bin/cosmovisor"

if [ -f "$UND_LOG_FILE" ]; then
  rm "${UND_LOG_FILE}"
fi

touch "${UND_LOG_FILE}"

if [ "$IS_RPC_NODE" = "1" ]; then
  mv /root/.und_mainchain/nginx.conf /etc/nginx/conf.d/nginx.conf
#  nginx -g 'daemon off;' &
  nginx &
fi

${RUN_WITH} run start &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' > "${UND_LOG_FILE}"))
