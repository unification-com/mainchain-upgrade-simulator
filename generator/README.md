# Network generator (Go)

Generates a simulator network from `config.json` - node homes, wallets, genesis files and `docker-compose.yml`. It is
replacing the bash generator (`scripts/bash/generate.sh` and `scripts/bash/lib/`) stage by stage. Until the port is
complete, `make gen` is still the bash generator and `make gen-go` runs this one.

| Stage | Ported                                                                                   | Status |
|-------|------------------------------------------------------------------------------------------|--------|
| G1    | typed config, output directories, third-party binaries, upgrade Go version               | done   |
| G2    | genesis: keys and wallet files, accounts, enterprise, static accounts, validators/gentx  |        |
| G3    | node `config.toml` / `app.toml`, Hermes, proxy, proposal files, `overview.json`          |        |
| G4    | `docker-compose.yml`                                                                     |        |
| G5    | output compared with bash on several configs, then `make gen` switches to this generator |        |

The config rules live in `schema/config.schema.json` and are enforced by the Node validator, which `make gen-go` runs
first; the generator only decodes the file, strictly, into the types in `internal/config`. The genesis-version `und`
and `gaiad` binaries still do the key and genesis work, as they do for the bash generator.

```bash
make gen-go                 # validate config.json, then generate
cd generator && go test ./...
```
