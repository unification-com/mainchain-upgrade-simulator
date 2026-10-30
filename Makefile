all: clean-gen build run-help

all-nc: clean-gen build-nc run-help

clean-gen: down clean gen

run-help:
	@echo ""
	@echo "for a full upgrade rehearsal in one command, run:  make sim"
	@echo "or, to drive it by hand, start 'make mon' and 'make tx' in separate windows, then run:  make up"
	@echo "('make up' alone does not upgrade - the tx runner submits the upgrade proposal)"
	@echo ""

# One command for a full upgrade rehearsal: fresh network, the tx runner (which submits the upgrade proposal) in the
# background, the network detached, and the monitor in the foreground. 'make down' stops everything afterwards.
sim: clean-gen build tx-bg
	docker compose up -d
	@echo ""
	@echo "network up, tx runner logging to out/tx_runner.log - quit the monitor with q, check the run with"
	@echo "'make verify', then stop everything with 'make down'"
	@echo ""
	@./scripts/bash/run_nodejs.sh monitor

# Validate config.json, then generate the network with the Go generator (generator/).
gen:
	@./scripts/bash/validate_config.sh config.json
	go -C generator run ./cmd/gen -root ..

# The bash generator the Go one replaced, kept as a fallback for now; it goes with scripts/bash/lib.
gen-bash:
	./scripts/bash/generate.sh

build:
	docker compose build

build-nc:
	docker compose build --no-cache

up:
	docker compose up

down: tx-stop
	@if [ -f docker-compose.yml ]; then docker compose down --remove-orphans; fi

mon:
	@./scripts/bash/run_nodejs.sh monitor

tx:
	@./scripts/bash/run_nodejs.sh tx_runner

# PASS/FAIL checks against the running network (upgrade applied, blocks, validators, IBC, a success per message type)
verify:
	@./scripts/bash/run_nodejs.sh verify

# tx runner in the background, in its own process group so tx-stop also stops the yarn and node processes under it
tx-bg: tx-stop
	@mkdir -p out
	@setsid nohup ./scripts/bash/run_nodejs.sh tx_runner > out/tx_runner.log 2>&1 < /dev/null & echo $$! > out/tx_runner.pid
	@echo "tx runner started in the background - log: out/tx_runner.log"

tx-stop:
	@if [ -f out/tx_runner.pid ]; then kill -- -$$(cat out/tx_runner.pid) 2>/dev/null || true; rm -f out/tx_runner.pid; echo "tx runner stopped"; fi

statesync:
	@./scripts/bash/get_statesync.sh

clean:
	@rm -f ./docker-compose.yml
	@rm -rf ./generated

.PHONY: all all-nc build build-nc up down gen gen-bash mon tx tx-bg tx-stop sim verify statesync clean run-help clean-gen
