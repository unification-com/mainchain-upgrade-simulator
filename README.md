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
- `apps.ibc.version` - the **Gaia release tag** (without the `v`) used for the IBC counterparty chain, e.g. `27.3.0`.
  Despite the key name it is not an `ibc-go` version
- `apps.ibc.hermes_version` - the Hermes relayer release
- `apps.cosmovisor.version` - the cosmovisor release the FUND nodes run under

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

If the network has been reconfigured and regenerated for a different version of `und` or Gaia, fully rebuild
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

It prints a `[PASS]`/`[FAIL]` line per check and exits non-zero if any fail (see 4.6). Some alarming-looking log
lines are expected along the way (see 4.7). Then stop everything,
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

| Variable           | Package     | Default                           | Purpose                                                                                    |
|--------------------|-------------|-----------------------------------|--------------------------------------------------------------------------------------------|
| `GENERATED_DIR`    | both        | the repo's `generated/` directory | Where `make gen` wrote its output. Only set it if that directory lives somewhere else.     |
| `LOG_LEVEL`        | `tx_runner` | `info`                            | Log verbosity.                                                                             |
| `USE_NO_WITH_VETO` | `tx_runner` | `false`                           | `true` adds No-with-veto to the random votes on non-upgrade proposals (can burn deposits). |

The monitor script can be run with the `mon` make target:

```bash
make mon
```

### 4.2 Run Transactions

The `tx_runner` script can be used to simulate most of the main transaction types on the network (sending, staking
streams, enterprise, wrkchains, beacons etc.). It runs on the host, not in a container, and also submits and votes on
the upgrade proposal. The proposal, and a WrkChain registration after the upgrade, go through the `und` CLI rather than
the signing client: they run inside `rpc1` with the binary the network is running, so the CLI itself is tested on both
versions and no host `und` is needed. Before bringing the composition up, install the Node dependencies as in
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

Hermes normally relays straight through the upgrade without help (`make verify` checks that packets were relayed after
it). If it has stopped relaying while its IBC client is still valid, restart it (an expired client - see 4.7 - is not
fixed by a restart):

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

### 4.7. What to expect during a rehearsal

Some log output looks like failure but is the normal shape of an upgrade:

- **`CONSENSUS FAILURE!!!` at `upgrade_height`.** Every FUND node logs `UPGRADE "<plan>" NEEDED at height: <h>`
  followed by `CONSENSUS FAILURE!!! ... failed to apply block` and a stack trace. This is how the old binary halts for
  an upgrade. cosmovisor then logs `upgrade detected, relaunching`, starts the new binary from
  `cosmovisor/upgrades/<plan>/bin/und`, and it logs `applying upgrade "<plan>" at height: <h>` and carries on.
- **The `tx_runner` waits out the halt.** It logs `websocket disconnected - probably upgrade in progress` and resumes
  when the chain does. It switches to the new binary's message shapes one block before `upgrade_height`, since the
  upgrade block is the first one the new binary executes. An occasional `account sequence mismatch` corrects itself on
  the wallet's next transaction.
- **Hermes logs `ERROR`s that are harmless.** `misbehaviour checking is being disabled ... could not extract header`
  repeats throughout; WebSocket / `failed to collect events` errors appear during the halt; a `will retry` client
  error can appear at start-up before both chains are ready.
- **Only a very long halt expires the IBC client.** Hermes's client `trusting_period` is 20 minutes
  (`templates/configs/hermes_config.toml`), the most the genesis 30-minute unbonding time allows. A halt longer than
  that expires the client and relaying stops for the rest of the run. Undelegated tokens take those 30 minutes to
  return to their wallets.

## 5. Example commands

Every generated wallet - validators, test accounts, BEACON and WRKChain owners, stream senders and receivers, IBC
accounts - is in `generated/assets/wallets/und/` (and `generated/assets/wallets/gaiad/`), mnemonic included. The
examples use the default ports from `example.config.json` (FUND `rpc1`: RPC 26760, REST 1320) and the `8-vaxildan`
plan; adjust them to your `config.json`.

Run the CLI inside a FUND node container. `cosmovisor/current` is always the binary that node is running, so the same
commands work before and after the upgrade:

```bash
UND="docker exec -i t_dn_fund_rpc1 /root/.und_mainchain/cosmovisor/current/bin/und"
NODE="--node tcp://localhost:26760"

$UND version
$UND query upgrade applied 8-vaxildan $NODE --output json
$UND query beacon beacon 1 $NODE --output json
$UND query stream streams $NODE --output json
$UND query staking params $NODE --output json
```

Or query REST from the host:

```bash
curl -s localhost:1320/cosmos/upgrade/v1beta1/applied_plan/8-vaxildan
curl -s localhost:1320/mainchain/stream/v1/streams/all | jq '.streams | length'
```

To sign transactions, recover generated wallets into a throwaway keyring in the container. The `tx_runner` signs with
the same wallets, so stop it first (`make tx-stop`) and give any of its pending transactions a block to clear, or
expect `account sequence mismatch`:

```bash
W=generated/assets/wallets/und
TX="--keyring-backend test --home /tmp/cli $NODE --chain-id FUND-DevNet-2 --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund -y"

jq -r .mnemonic $W/test10.json | $UND keys add test10 --recover --keyring-backend test --home /tmp/cli
jq -r .mnemonic $W/stream_receiver2.json | $UND keys add stream_receiver2 --recover --keyring-backend test --home /tmp/cli

# send 1 FUND
$UND tx bank send test10 $(jq -r .address_bech32 $W/test9.json) 1000000000nund $TX

# claim from a stream - from 8-vaxildan on, streams are per denom, so claim takes [sender] [denom]
$UND tx stream claim $(jq -r .address_bech32 $W/stream_sender2.json) nund --from stream_receiver2 $TX

$UND query tx <TX_HASH> $NODE --output json
```
