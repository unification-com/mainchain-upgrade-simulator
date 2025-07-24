#############################################################
# golang:1.21-alpine container

FROM golang:1.21-alpine AS golang1_21-base
WORKDIR /root
ENV PACKAGES="git make gcc libc-dev jq curl wget bash gcc"
RUN apk update && apk add --no-cache ${PACKAGES} --upgrade grep --upgrade sed

#############################################################
# golang:1.23-alpine container

FROM golang:1.23-alpine AS golang1_23-base
WORKDIR /root
ENV PACKAGES="git make gcc libc-dev jq curl wget bash gcc"
RUN apk update && apk add --no-cache ${PACKAGES} --upgrade grep --upgrade sed

#############################################################
# cosmovisor builder container

FROM golang1_21-base AS und-cosmovisor

ARG COSMOVISOR_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv${COSMOVISOR_VER}/cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz && \
    tar  -C /usr/local/bin/ -zxf cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz

#############################################################
# und genesis downloader container

FROM golang1_23-base AS und-genesis-downloader

ARG UND_GENESIS_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/unification-com/mainchain/releases/download/v${UND_GENESIS_VER}/und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    tar -C /usr/local/bin/ -xzf und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    mv /usr/local/bin/und /usr/local/bin/und

#############################################################
# und upgrade builder container

FROM golang1_23-base AS und-builder

ARG UND_UPGRADE_BRANCH

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    git clone https://github.com/unification-com/mainchain.git && \
    cd /root/mainchain && \
    git checkout ${UND_UPGRADE_BRANCH} && \
    export LEDGER_ENABLED=false && \
    make build && \
    /root/mainchain/build/und version && \
    mv /root/mainchain/build/und /usr/local/bin/und

#############################################################
# Final container

#FROM alpine:latest
FROM nginx:stable-alpine

WORKDIR /root/

ENV PACKAGES="wget curl jq bash"
RUN apk add --no-cache ${PACKAGES}

ARG NODE_NAME
ARG UPGRADE_PLAN_NAME

RUN mkdir -p /root/.und_mainchain/cosmovisor/genesis/bin && \
    mkdir -p /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin

ENV LOCAL=/usr/local
ENV DAEMON_NAME=und
ENV DAEMON_HOME="/root/.und_mainchain"
ENV DAEMON_RESTART_AFTER_UPGRADE=true
ENV DAEMON_RESTART_DELAY=5s
ENV UNSAFE_SKIP_BACKUP=false
ENV DAEMON_SHUTDOWN_GRACE=5s

COPY --from=und-cosmovisor /usr/local/bin/cosmovisor ${LOCAL}/bin/cosmovisor
COPY --from=und-genesis-downloader /usr/local/bin/und /root/.und_mainchain/cosmovisor/genesis/bin/und
COPY --from=und-builder /usr/local/bin/und /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin/und

COPY generated/assets/fund_net/${NODE_NAME} /root/.und_mainchain
COPY generated/assets/scripts/run_node.sh ./

RUN chmod +x run_node.sh
