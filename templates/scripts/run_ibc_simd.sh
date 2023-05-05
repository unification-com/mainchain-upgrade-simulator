#!/bin/bash

SIMD_LOG_FILE="/root/out/simd.log"

if [ -f "$SIMD_LOG_FILE" ]; then
  rm "${SIMD_LOG_FILE}"
fi

touch "${SIMD_LOG_FILE}"

/usr/local/bin/simd start --home /root/.simapp &> >(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' > "${SIMD_LOG_FILE}"))
