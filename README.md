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

## 1. Configuring a simulation DevNet

The suite expects to find a `config.json`. The `example.config.json` file can be used as a template.

The `apps` object is used to define the upgrade parameters, such as the version to upgrade from and to:

- `apps.und.genesis.version` - the `und` version which will be used as the genesis version to upgrade **from**.
- `apps.und.upgrade.branch` - the `und` version which the network will upgrade **to**. This is a Git branch
- `apps.und.upgrade.upgrade_height` - the height at which the upgrade will take place
- `apps.und.upgrade.upgrade_plan_name` - the upgradr plan name. This must match the plan in the actual upgrade branch
- `apps.ibc.version` - the version of `ibc-go` to use for the IBC network.

Additionally, the size of the network can be configured:

- `apps.und.nodes.num_validators` - number of validator nodes to run
- `apps.und.nodes.num_sentries` - number of sentries to run
- `apps.und.nodes.num_seeds` - number of seed nodes to run
- `apps.und.nodes.num_rpcs` - number of RPC nodes to run

Most other configuration values can be left as their defaults.

## 2. Generate the network

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

### 4.1. Monitoring

A simple monitoring script can optionally be run while the network is up, which will output some stats. Before bringing
the composition up, in a separate terminal, run:

```bash
make mon
```

### 4.2. Run the network

The network can be brought up by running:

```bash
make up
```

While the network is running, logs are streamed to the `out` directory.

... and when finished, it can be brought down using:

```bash
Ctrl+C
make down
```

### 4.3 Simulate node going offline

Pause a container to simulate a node going offline, for example

```bash
docker pause t_dn_fund_sentry1
```

Bring it back online using

```bash
docker unpause t_dn_fund_sentry1
```

## 6. Example commands

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

TMP - CHECKING MIN COMMISSION - EXECUTE AFTER UPGRADE & PROPOSAL PASSES
This should occur (suing default config) at around block 75

```bash
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query staking params --home /root/.und_cli_txs

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade query staking validators --home /root/.und_cli_txs

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator1 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator2 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund
docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator3 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund

docker exec -it t_dn_tx_runner /usr/local/bin/und_upgrade tx staking edit-validator --commission-rate "0.05" --from validator4 --home /root/.und_cli_txs --keyring-backend test --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund
```



