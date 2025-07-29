all: clean-gen build run-help

all-nc: clean-gen build-nc run-help

clean-gen: down clean gen

run-help:
	@echo ""
	@echo "ensure monitor and tx runner scripts are running in separate windows, then run:"
	@echo ""
	@echo "  make up"
	@echo ""

gen:
	./scripts/bash/generate.sh

build:
	docker compose build

build-nc:
	docker compose build --no-cache

up:
	docker compose up

down:
	docker compose down --remove-orphans

mon:
	@./scripts/bash/run_nodejs.sh monitor

tx:
	@./scripts/bash/run_nodejs.sh tx_runner

statesync:
	@./scripts/bash/get_statesync.sh

clean:
	@rm -f ./docker-compose.yml
	@rm -rf ./generated

.PHONY: all all-nc build build-nc up down gen mon tx statesync clean run-help clean-gen
