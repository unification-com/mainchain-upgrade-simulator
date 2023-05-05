FROM golang:1.19-alpine3.15 AS und_builder

RUN apk update && \
    apk upgrade && \
    apk add git make gcc libc-dev jq curl wget bash gcc --no-cache --upgrade grep --upgrade sed

ENV GO111MODULE="on"
ENV LEDGER_ENABLED="false"

ARG UND_GENESIS_VER
ARG UND_UPGRADE_BRANCH
ARG V_PREFIX
ARG COSMOVISOR_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/unification-com/mainchain/releases/download/${V_PREFIX}${UND_GENESIS_VER}/und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    tar -C /usr/local/bin/ -xzf und_v${UND_GENESIS_VER}_linux_x86_64.tar.gz && \
    mv /usr/local/bin/und /usr/local/bin/und_genesis && \
    wget https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv${COSMOVISOR_VER}/cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz && \
    tar  -C /usr/local/bin/ -zxf cosmovisor-v${COSMOVISOR_VER}-linux-amd64.tar.gz && \
    git clone https://github.com/unification-com/mainchain.git && \
    cd /root/mainchain && \
    git checkout ${UND_UPGRADE_BRANCH} && \
    make build && \
    /root/mainchain/build/und version && \
    mv /root/mainchain/build/und /usr/local/bin/und_upgrade

FROM golang:1.19-alpine3.15

WORKDIR /root/

RUN mkdir -p /usr/local/bin && \
    mkdir -p /root/out && \
    apk update && \
    apk upgrade && \
    apk add git make jq curl wget bash nano --no-cache --upgrade grep --upgrade sed

ARG NODE_NAME
ARG UPGRADE_PLAN_NAME

RUN mkdir -p /root/.und_mainchain/cosmovisor/genesis/bin && \
    mkdir -p /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin

COPY --from=und_builder /usr/local/bin/und_genesis /root/.und_mainchain/cosmovisor/genesis/bin/und
COPY --from=und_builder /usr/local/bin/und_upgrade /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin/und
COPY --from=und_builder /usr/local/bin/cosmovisor /usr/local/bin/

RUN /root/.und_mainchain/cosmovisor/upgrades/${UPGRADE_PLAN_NAME}/bin/und version

COPY generated/assets/nodes/${NODE_NAME}/.und_mainchain /root/.und_mainchain
COPY generated/assets/scripts/run_node.sh ./

RUN chmod +x run_node.sh
