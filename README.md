# Unification DevNet Upgrade Simulator

A set of configurable scripts and Docker containers that can be used to generate and test an upgradable `DevNet`, in
order to test an upgrade from an `OLD_VERSION` to a `NEW_VERSION` of `und` (for example, from v1.6.3 to v1.7.0)

For simplicity, the simulation will use the `OLD_VERSION` for genesis, and currently only supports testing one
upgrade plan.

The test network consists of a configurable number of Unification Mainchain validators, sentries, seeds and RPCs,
in addition to a small third party IBC enabled chain to test IBC transfers.

The network is also configured to run:

- A number of scripts to randomly generate and broadcast transactions, including `enterprise`, `beacon`, `wrkchain`,
standard Cosmos Txs and IBC transfers
- A Hermes IBC relayer to process IBC transfers between the chains
- An NGINX proxy server to allow connections from, for example, Web Wallet.

The network will also automatically generate the upgrade Governance proposal and vote "yes" for all validators.

This suite has been used internally to test upgrading the following:

- 1.5.1 -> 1.6.3
- 1.6.3 -> 1.7.0
- 1.7.0 -> 1.8.1
- 1.8.2 -> 1.9.0
- 1.9.x -> 1.10.x
- 1.10.x -> 1.11.x
- 1.11.x -> 1.12.x

## 1. Configuring a simulation DevNet

The suite expects to find a `config.json`. The `example.config.json` file can be used as a template.

The `apps` object is used to define the upgrade parameters, such as the version to upgrade from and to:

- `apps.und.genesis.version` - the `und` version which will be used as the genesis version to upgrade **from**.
- `apps.und.upgrade.branch` - the `und` version which the network will upgrade **to**. This is a Git branch or tag of
  `mainchain`; the Go version used to build it is read from that ref's `go.mod` when the network is generated
- `apps.und.upgrade.upgrade_height` - the height at which the upgrade will take place
- `apps.und.upgrade.upgrade_plan_name` - the upgrade plan name. This must match the plan in the actual upgrade branch
- `apps.ibc.version` - the version of `ibc-go` to use for the IBC network.

Additionally, the size of the network can be configured:

- `apps.und.nodes.num_validators` - number of validator nodes to run
- `apps.und.nodes.num_sentries` - number of sentries to run
- `apps.und.nodes.num_seeds` - number of seed nodes to run
- `apps.und.nodes.num_rpcs` - number of RPC nodes to run

Most other configuration values can be left as their defaults.

## 2. Generate the network

`make gen` first validates `config.json` against `schema/config.schema.json` and stops, before anything is generated,
if a field is misspelt, missing or out of range. The validator is part of the Node workspace, so install that once
(Node 22, the same install used by the monitor and tx runner in section 4):

```bash
cd scripts/nodejs
nvm use
yarn install
```

To check a config on its own: `yarn --cwd scripts/nodejs workspace @simulator/config validate [path/to/config.json]`
(defaults to `config.json`; a relative path is taken from the repo root).

Once configured, the network can be generated. This will generate all the necessary genesis, scripts, wallets and node
config files etc. required. Run:

```bash 
make gen
```

All generated files will be saved to the `generated/assets` directory. Additionally, a `docker-compose.yml` file
will be generated in this root directory.

## 3. Build the Docker containers

Now we have the configuration files, we can build the Docker containers:

```bash
make build
```

If the network has been reconfigured and regenerated for a different version of `und` or the IBC `simd`, fully rebuild
the containers without using Docker cache:

```bash
make build-nc
```

## 4. Running

### 4.0. One-command rehearsal (recommended)

```bash
make sim
```

`make sim` regenerates the network from `config.json`, rebuilds the images, starts the `tx_runner` in the background
(it submits the upgrade proposal, then drives transactions; its log is `out/tx_runner.log`), brings the network up and
attaches the monitor. Once the chain is well past `upgrade_height`, quit the monitor with `q` and check the run:

```bash
make verify
```

It prints a `[PASS]`/`[FAIL]` line per check and exits non-zero if any fail (see 4.6). Then stop everything,
including the background `tx_runner`, with:

```bash
make down
```

> **`make up` on its own does not perform the upgrade.** The upgrade proposal is submitted by the `tx_runner`
> (`make tx`). Without it the chain keeps producing blocks past `upgrade_height` and never upgrades. Use `make sim`,
> or run `make tx` alongside `make up`.

The sections below run the pieces individually.

### 4.1. Monitoring

A simple monitoring script can optionally be run while the network is up, which will output some stats. Before bringing
the composition up, in a separate terminal, first install the Node dependencies. The monitor, the `tx_runner` and
`verify` are packages in one yarn workspace, so a single install covers them all:

```bash
cd scripts/nodejs
nvm use
yarn install
```

Each package also reads an optional `.env` file in its own directory (`scripts/nodejs/packages/monitor/.env`,
`scripts/nodejs/packages/tx_runner/.env`):

| Variable        | Package     | Default                                       | Purpose                                                                                     |
|-----------------|-------------|-----------------------------------------------|---------------------------------------------------------------------------------------------|
| `GENERATED_DIR` | both        | the repo's `generated/` directory             | Where `make gen` wrote its output. Only set it if that directory lives somewhere else.     |
| `UND_BIN`       | `tx_runner` | `third_party/bin/und_<genesis version>`       | The `und` binary used to submit the upgrade proposal (`make gen` downloads the default).   |
| `LOG_LEVEL`     | `tx_runner` | `info`                                        | Log verbosity.                                                                              |

The monitor script can be run with the `mon` make target:

```bash
make mon
```

### 4.2 Run Transactions

The `tx_runner` script can be used to simulate most of the main transaction types on the network (sending, staking
streams, enterprise, wrkchains, beacons etc.). Before bringing the composition up, install the Node dependencies as in
4.1 if you have not already.

The `tx_runner` script can be run with the `tx` make target:

```bash
make tx
```

### 4.3. Run the network

The network can be brought up by running the following. Remember that `make up` alone does not upgrade the network -
the `tx_runner` (4.2) must be running too, or use `make sim` (4.0).

```bash
make up
```

While the network is running, logs are streamed to the `out` directory.

... and when finished, it can be brought down using:

```bash
Ctrl+C
make down
```

### 4.4 Simulate node going offline

Pause a container to simulate a node going offline, for example

```bash
docker pause t_dn_fund_sentry1
```

Bring it back online using

```bash
docker unpause t_dn_fund_sentry1
```

### 4.5 Restart Hermes

After an upgrade has occurred, the `hermes` container will need restarting, for example:

```bash
docker restart t_dn_ibc_hermes
```

### 4.6. Verify a run

With the network still up and the chain at least 10 blocks past `upgrade_height`:

```bash
make verify
```

Checks, all against the running network (the plan, height and nodes come from `generated/network/overview.json`):

- the upgrade plan was applied at exactly `upgrade_height`
- the chain is at least 10 blocks past it and its latest block is under a minute old
- every node and the Hermes container is running
- every validator signed at least one of the last 10 blocks
- an IBC transfer channel is open on both chains
- at least one successful transaction per message type the `tx_runner` sends, plus Hermes's IBC packet relaying, both
  before the upgrade and from `upgrade_height` on (the upgrade block is the first one the new binary runs) - so both
  binaries are proven to handle every message. The upgrade proposal itself is only needed before

Exit code 0 means every check passed. To add a check, add an entry to
`scripts/nodejs/packages/verify/src/checks.mjs` - a message type is one line in `EXPECTED_MSGS`.

## 5. Example commands

The `t_dn_tx_runner` container can also be used to run arbitrary queries etc., for example

Pre-upgrade, using the `und_genesis` binary:

```bash
docker exec -it t_dn_tx_runner /bin/bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis keys show t1 -a --keyring-backend test --keyring-dir /root/.und_cli_txs
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query account <WALLET_ADDR> --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query tx <TX_HASH> --home /root/.und_cli_txs --output json

docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query gov proposals --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query enterprise orders --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query beacon search --home /root/.und_cli_txs --output json | jq '.beacons | length'

docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query beacon beacon 1 --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query wrkchain wrkchain 1 --home /root/.und_cli_txs --output json

docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query beacon params --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query wrkchain params --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_genesis query staking params --home /root/.und_cli_txs --output json
```

Post-upgrade, using the `und_upgrade` binary:

```bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade keys show t1 -a --keyring-backend test --keyring-dir /root/.und_cli_txs

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query beacon beacon 1 --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query wrkchain wrkchain 1 --home /root/.und_cli_txs --output json

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query beacon params --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query wrkchain params --home /root/.und_cli_txs --output json
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query staking params --home /root/.und_cli_txs --output json
```

IBC Examples

```bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx ibc-transfer transfer transfer channel-0 $(docker exec -it t_dn_tx_runner /usr/local/bin/gaiad keys show ibc_gaiad3 -a --keyring-backend test --keyring-dir /root/.gaiad_cli_txs) 10000000000nund \
  --home /root/.und_cli_txs \
  --keyring-backend test \
  --node http://172.25.1.8:26906 \
  --chain-id FUND-DevNet-2 \
  --from ibc_und1 \
  --gas auto \
  --gas-adjustment 1.2 \
  --gas-prices 25.0nund \
  -y
  
  
docker exec -it t_dn_tx_runner /usr/local/bin/gaiad tx ibc-transfer transfer transfer channel-0 $(docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade keys show ibc_und1 -a --keyring-backend test --keyring-dir /root/.und_cli_txs) 10000000000ibc/D6CFF2B192E06AFD4CD78859EA7CAD8B82405959834282BE87ABB6B957939618 \
  --home /root/.gaiad_cli_txs \
  --keyring-backend test \
  --node http://172.25.1.12:27001 \
  --chain-id IBC-SimApp-DevNet \
  --from ibc_gaiad3 \
  --gas auto \
  --gas-adjustment 1.2 \
  --gas-prices 0.1stake \
  -y
```

Streams

```bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query stream params --home /root/.und_cli_txs

# calculate flow rate
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query stream calculate_flow --coin 1000000000000nund --period day --duration 1 --home /root/.und_cli_txs

# get wallet address of receiver
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade keys show ps_r1 -a --keyring-backend test --keyring-dir /root/.und_cli_txs

# create stream
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx stream create ADDRESS_FROM_ABOVE 1000000000000nund 11574074 \
  --from ps_s1 \
  --keyring-backend test \
  --node http://172.25.1.8:26906 \
  --chain-id FUND-DevNet-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 25.0nund \
  --home /root/.und_cli_txs

# query streams
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query stream streams --home /root/.und_cli_txs

# get wallet address of sender
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade keys show ps_s1 -a --keyring-backend test --keyring-dir /root/.und_cli_txs

# Claim form stream
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx stream claim ADDRESS_FROM_ABOVE \
  --from ps_r1 \
  --keyring-backend test \
  --node http://172.25.1.8:26906 \
  --chain-id FUND-DevNet-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 25.0nund \
  --home /root/.und_cli_txs

# update flow
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx stream update-flow RECEIVER_WALLET_ADDRESS 277777777 \
  --from ps_s1 \
  --keyring-backend test \
  --node http://172.25.1.8:26906 \
  --chain-id FUND-DevNet-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 25.0nund \
  --home /root/.und_cli_txs
  
# topup deposit
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx stream topup RECEIVER_WALLET_ADDRESS 1000000000000nund \
  --from ps_s1 \
  --keyring-backend test \
  --node http://172.25.1.8:26906 \
  --chain-id FUND-DevNet-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 25.0nund \
  --home /root/.und_cli_txs

# query tx hash reference command
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query tx TX_HASH --home /root/.und_cli_txs

```



TMP - CHECKING MIN COMMISSION - EXECUTE AFTER UPGRADE & PROPOSAL PASSES
This should occur (using the default config in `example.config.json`) at around block 75

```bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query staking params --home /root/.und_cli_txs

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query staking validators --home /root/.und_cli_txs

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator1 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator2 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator3 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator4 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund
```

