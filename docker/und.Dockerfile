# check=skip=InvalidDefaultArgInFrom
#############################################################
# (the check is skipped on purpose: GO_VERSION has no default because the generator always supplies it, and a
# default would bring back the hard-coded Go version this file exists to avoid)
#
# Mainchain node image for the upgrade simulator: cosmovisor, the genesis und (a release download) and the upgrade
# und (built from source) on a slim Alpine runtime. Every version arrives as a build arg from the generated
# docker-compose.yml, so nothing version-specific is hard-coded here.
#
# GO_VERSION is the major.minor golang image tag the upgrade binary needs; the generator reads it from the target
# ref's go.mod (scripts/bash/lib/config.sh).

ARG GO_VERSION
ARG ALPINE_VERSION=3.22

#############################################################
# release downloads - no Go toolchain needed

FROM alpine:${ALPINE_VERSION} AS fetch
RUN apk add --no-cache wget tar
WORKDIR /root
RUN mkdir -p /out

FROM fetch AS cosmovisor
ARG COSMOVISOR_VER
RUN wget -q https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv${COSMOVISOR_VER}/cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz && \
    tar -C /out -zxf cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz

FROM fetch AS und-genesis
ARG UND_GENESIS_VER
RUN wget -q https://github.com/unification-com/mainchain/releases/download/v${UND_GENESIS_VER}/und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    tar -C /out -xzf und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    /out/und version

#############################################################
# upgrade binary, built from source (static: CGO off, no ledger)

FROM golang:${GO_VERSION}-alpine AS und-upgrade
RUN apk add --no-cache git make gcc libc-dev bash
ARG UND_UPGRADE_BRANCH
WORKDIR /root
RUN git clone https://github.com/unification-com/mainchain.git && \
    cd /root/mainchain && \
    git checkout ${UND_UPGRADE_BRANCH} && \
    LEDGER_ENABLED=false CGO_ENABLED=0 make build && \
    /root/mainchain/build/und version

#############################################################
# runtime - both und binaries are statically linked, so no Go toolchain here

FROM alpine:${ALPINE_VERSION}

WORKDIR /root/

RUN apk add --no-cache bash wget curl jq nginx

ARG NODE_NAME
ARG UPGRADE_PLAN_NAME

ENV DAEMON_NAME=und
ENV DAEMON_HOME="/root/.und_mainchain"
ENV DAEMON_RESTART_AFTER_UPGRADE=true
ENV DAEMON_RESTART_DELAY=5s
ENV UNSAFE_SKIP_BACKUP=false
ENV DAEMON_SHUTDOWN_GRACE=5s

COPY --from=cosmovisor /out/cosmovisor /usr/local/bin/cosmovisor
COPY --from=und-genesis /out/und /root/.und_mainchain/cosmovisor/genesis/bin/und
COPY --from=und-upgrade /root/mainchain/build/und /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin/und

COPY generated/assets/fund_net/${NODE_NAME} /root/.und_mainchain
COPY generated/assets/scripts/run_node.sh ./

RUN chmod +x run_node.sh
