# Network generator (Go)

Generates a simulator network from `config.json` - node homes, wallets, genesis files and `docker-compose.yml`. It
replaced the bash generator (`scripts/bash/generate.sh` and `scripts/bash/lib/`), which stays available as
`make gen-bash` until it is removed.

| Stage | Ported                                                                                   | Status |
|-------|------------------------------------------------------------------------------------------|--------|
| G1    | typed config, output directories, third-party binaries, upgrade Go version               | done   |
| G2    | genesis: keys and wallet files, accounts, enterprise, static accounts, nodes, gentxs     | done   |
| G3    | node `config.toml` / `app.toml`, nginx proxies, Hermes config, upgrade proposal          | done   |
| G4    | `docker-compose.yml`, `overview.json`                                                    | done   |
| G5    | output compared with bash on several configs, then `make gen` switches to this generator | done   |

The config rules live in `schema/config.schema.json` and are enforced by the Node validator, which `make gen` runs
first; the generator only decodes the file, strictly, into the types in `internal/config`. The genesis-version `und`
and `gaiad` binaries still do the key and genesis work, as they do for the bash generator.

```bash
make gen                    # validate config.json, then generate
cd generator && go test ./...
```

## Checking against the bash generator

Generate the same config with both, then compare. `gencompare` masks what is random on every run (keys, mnemonics,
addresses, node IDs, signatures, times, validator stakes) and compares JSON and YAML structurally; `-skip` leaves out
files by glob. `docker-compose.yml` is written outside `generated/`, so copy it in to include it.

```bash
make gen-bash && cp -r generated /tmp/bash-generated && cp docker-compose.yml /tmp/bash-generated/
make gen && cp docker-compose.yml generated/
go -C generator run ./cmd/gencompare /tmp/bash-generated generated
rm generated/docker-compose.yml
```

Intended differences from the bash output:

- a validator's `min_self` override reaches its gentx - the bash generator computed it but never passed it on
- wallet files have no `key_files` (nothing reads them since the tx runner signs CLI transactions in a node container)
- node descriptors have no `val_pubkey_escaped` (it only fed the bash gentx command)
- no `network/docker/` counter files, `stake_*.json` or `network/hermes.json` (bash-internal state, kept in memory)
- compose `command` is in exec form (`["/bin/bash", "-c", "cd /root && ./run_node.sh"]`) - the same commands as the
  bash generator's folded multi-line string

The nginx proxy and upgrade proposal templates in `templates/configs/` are shared by both generators; node TOML files
are edited in place (`internal/tomledit`), changing only the lines the bash generator's `tomli` calls changed.
