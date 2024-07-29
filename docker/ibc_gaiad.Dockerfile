FROM golang:1.22-alpine

RUN apk update && \
    apk upgrade && \
    apk add git make gcc libc-dev jq curl wget bash gcc nano --no-cache --upgrade grep --upgrade sed

ENV GO111MODULE="on"
ENV LEDGER_ENABLED="false"

ARG IBC_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/cosmos/gaia/releases/download/v${IBC_VER}/gaiad-v${IBC_VER}-linux-amd64 && \
    mv gaiad-v${IBC_VER}-linux-amd64 /usr/local/bin/gaiad && \
    chmod +x /usr/local/bin/gaiad && \
    /usr/local/bin/gaiad version

RUN rm -rf /root/.simapp

COPY generated/assets/ibc_net/node /root/.simapp
COPY generated/assets/scripts/run_ibc_gaiad.sh ./

RUN chmod +x run_ibc_gaiad.sh
