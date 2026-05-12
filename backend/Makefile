SHELL := /bin/bash

.PHONY: help tidy build test run migrate up down logs psql redis-cli

help:
	@awk 'BEGIN{FS=":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

tidy:         ## go mod tidy
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && go mod tidy

build:        ## build all packages
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && go build ./...

test:         ## run unit tests
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && go test ./... -count=1

run:          ## run the server
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && go run ./cmd/server

migrate:      ## apply pending migrations
	cd $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST)))) && go run ./cmd/server -migrate

up:           ## docker compose up -d (postgres + redis + minio)
	docker compose -f ../docker-compose.yml up -d

down:         ## docker compose down
	docker compose -f ../docker-compose.yml down

logs:         ## follow docker compose logs
	docker compose -f ../docker-compose.yml logs -f

psql:         ## psql into local dripadvisor db
	docker compose -f ../docker-compose.yml exec postgres psql -U dripadvisor -d dripadvisor

redis-cli:    ## redis-cli on local redis
	docker compose -f ../docker-compose.yml exec redis redis-cli
