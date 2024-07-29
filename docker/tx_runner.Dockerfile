FROM golang:1.22-alpine

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
    wget https://github.com/cosmos/gaia/releases/download/v${IBC_VER}/gaiad-v${IBC_VER}-linux-amd64 && \
    mv gaiad-v${IBC_VER}-linux-amd64 /usr/local/bin/gaiad && \
    chmod +x /usr/local/bin/gaiad && \
    /usr/local/bin/und_genesis version --home /root/.und_mainchain && \
    /usr/local/bin/und_upgrade version --home /root/.und_mainchain && \
    /usr/local/bin/gaiad version --home /root/.simapp && \
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest && \
    mkdir /root/txs && mkdir /root/txs/scripts

COPY generated/assets/scripts ./scripts/
COPY generated/assets/txs ./txs/
COPY generated/assets/wallet_keys/und ./.und_mainchain/keyring-test
COPY generated/assets/wallet_keys/gaiad ./.simapp/keyring-test
