FROM golang:1.23-alpine AS gaiad-base

RUN apk update && \
    apk upgrade && \
    apk add git make gcc libc-dev jq curl wget bash gcc nano --no-cache --upgrade grep --upgrade sed && \
    apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing grpcurl

ENV GO111MODULE="on"
ENV LEDGER_ENABLED="false"

ARG IBC_VER

WORKDIR /root

RUN mkdir -p /usr/local/bin && \
    wget https://github.com/cosmos/gaia/releases/download/v${IBC_VER}/gaiad-v${IBC_VER}-linux-amd64 && \
    mv gaiad-v${IBC_VER}-linux-amd64 /usr/local/bin/gaiad && \
    chmod +x /usr/local/bin/gaiad && \
    /usr/local/bin/gaiad version

FROM nginx:stable-alpine

ENV PACKAGES="wget curl jq bash"
RUN apk add --no-cache ${PACKAGES}

ARG NODE_NAME

WORKDIR /root

RUN rm -rf /root/.simapp

COPY --from=gaiad-base /usr/local/bin/gaiad /usr/local/bin/gaiad

COPY generated/assets/gaiad_net/${NODE_NAME} /root/.simapp
COPY generated/assets/scripts/run_ibc_gaiad.sh ./

RUN chmod +x run_ibc_gaiad.sh
