FROM golang:1.19-alpine3.15

RUN apk update && \
    apk upgrade && \
    apk add git make gcc libc-dev jq curl wget bash gcc nano --no-cache --upgrade grep --upgrade sed

ENV GO111MODULE="on"
ENV LEDGER_ENABLED="false"

ARG IBC_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    git clone https://github.com/cosmos/ibc-go && \
    cd ibc-go && \
    git checkout v${IBC_VER} && \
    make build && \
    mv build/simd /usr/local/bin/simd && \
    /usr/local/bin/simd version

RUN rm -rf /root/.simapp

COPY generated/assets/ibc_net/node /root/.simapp
COPY generated/assets/scripts/run_ibc_simd.sh ./

RUN chmod +x run_ibc_simd.sh
