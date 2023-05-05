gen:
	./generate.sh

build:
	docker-compose build

build-nc:
	docker-compose build --no-cache

up:
	docker-compose up

down:
	docker-compose down --remove-orphans

clean:
	@rm -f ./docker-compose.yml
	@rm -rf ./out
	@rm -rf ./generated

.PHONY: build build-nc up down gen clean
