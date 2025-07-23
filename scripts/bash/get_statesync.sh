#!/bin/bash

set -e

REST_URL="http://localhost:1320"
JQ_BIN="/usr/bin/jq"
DIV=10 # e.g. 1000
DIVF="0" # e.g. 000 id DIV is 1000

CURRENT_HEIGHT=$(curl -s "${REST_URL}"/cosmos/base/tendermint/v1beta1/blocks/latest | "${JQ_BIN}" -r '.block.header.height')
TRUST_HEIGHT=$(echo "${CURRENT_HEIGHT}" | awk '{printf "%d'${DIVF}'\n", $0 / '${DIV}'}')
TRUST_HASH=$(curl -s "${REST_URL}"/cosmos/base/tendermint/v1beta1/blocks/"${TRUST_HEIGHT}" | "${JQ_BIN}" -r '.block_id.hash' | base64 -d | hexdump --no-squeezing --format '/1 "%02x"' | tr '[:lower:]' '[:upper:]')

echo "CURRENT_HEIGHT = ${CURRENT_HEIGHT}"
echo "TRUST_HEIGHT = ${TRUST_HEIGHT}"
echo "TRUST_HASH = ${TRUST_HASH}"
