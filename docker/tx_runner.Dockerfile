FROM golang:1.19-alpine3.15

RUN apk update && \
    apk upgrade && \
    apk add git make gcc libc-dev jq curl wget bash gcc openssl --no-cache --upgrade grep --upgrade sed

ENV GO111MODULE="on"
ENV LEDGER_ENABLED="false"

ARG IBC_VER
ARG UND_GENESIS_VER
ARG UND_UPGRADE_BRANCH
ARG V_PREFIX

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/unification-com/mainchain/releases/download/${V_PREFIX}${UND_GENESIS_VER}/und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    tar -C /usr/local/bin/ -xzf und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    mv /usr/local/bin/und /usr/local/bin/und_genesis && \
    git clone https://github.com/unification-com/mainchain.git && \
    cd /root/mainchain && \
    git checkout ${UND_UPGRADE_BRANCH} && \
    make build && \
    mv /root/mainchain/build/und /usr/local/bin/und_upgrade && \
    git clone https://github.com/cosmos/ibc-go && \
    cd ibc-go && \
    git checkout v${IBC_VER} && \
    make build && \
    mv build/simd /usr/local/bin/simd && \
    /usr/local/bin/und_genesis version --home /root/.und_mainchain && \
    /usr/local/bin/und_upgrade version --home /root/.und_mainchain && \
    /usr/local/bin/simd version --home /root/.simapp

COPY generated/assets/scripts ./
COPY generated/assets/keys/und ./.und_mainchain/keyring-test
COPY generated/assets/keys/simd ./.simapp/keyring-test
