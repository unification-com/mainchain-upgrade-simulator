all: down clean gen build up

all-nc: clean gen build-nc up

gen:
	./scripts/generate.sh

build:
	docker-compose build

build-nc:
	docker-compose build --no-cache

up:
	docker-compose up

down:
	docker-compose down --remove-orphans

mon:
	@./scripts/monitor.sh

clean:
	@rm -f ./docker-compose.yml
	@rm -rf ./out
	@rm -rf ./generated

.PHONY: all all-nc build build-nc up down gen mon clean
