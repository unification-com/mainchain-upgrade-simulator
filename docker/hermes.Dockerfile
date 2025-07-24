FROM ubuntu:24.04

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install git make gcc libc-dev jq curl wget bash gcc nano build-essential netcat-traditional --upgrade grep --upgrade sed -y

WORKDIR /root

ARG HERMES_VER

RUN mkdir -p /usr/local/bin && \
    mkdir -p /root/.hermes && \
    wget https://github.com/informalsystems/hermes/releases/download/v${HERMES_VER}/hermes-v${HERMES_VER}-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xzvf hermes-v${HERMES_VER}-x86_64-unknown-linux-gnu.tar.gz && \
    mv hermes /usr/local/bin/hermes

ARG MNEMONIC
ARG CHAIN_ID
ARG IBC_CHAIN_ID

COPY generated/assets/hermes/config.toml /root/.hermes/config.toml
COPY generated/assets/scripts/run_hermes.sh ./

RUN echo "${MNEMONIC}" > /root/.hermes/relayer_mnemonic && \
    chmod +x run_hermes.sh && \
    /usr/local/bin/hermes keys add --chain "${CHAIN_ID}" --hd-path "m/44'/5555'/0'/0/0" --key-name fund_relayer --mnemonic-file /root/.hermes/relayer_mnemonic && \
    /usr/local/bin/hermes keys add --chain "${IBC_CHAIN_ID}" --key-name simapp_relayer --mnemonic-file /root/.hermes/relayer_mnemonic
