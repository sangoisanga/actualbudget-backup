SHELL := /bin/bash

SCRIPT_FILES := scripts/includes.sh scripts/backup.sh scripts/entrypoint.sh
TEST_SCRIPT_FILES := tests/test.sh \
	tests/units/backup-zip-file/test.sh \
	tests/units/check-rclone-config-exists/test.sh \
	tests/units/check-rclone-flags-valid/test.sh
TEST_BASE_IMAGE ?= actualbudget-backup:test-base
TEST_IMAGE ?= actualbudget-backup:test

.PHONY: lint test test-node check-docker test-image test-container clean-test

lint:
	shfmt -d $(SCRIPT_FILES) $(TEST_SCRIPT_FILES)
	shellcheck $(SCRIPT_FILES) $(TEST_SCRIPT_FILES)
	node --check scripts/download-actual-budget.js
	node --check tests/download-actual-budget.test.js
	node --check tests/fixtures/js-modules/@actual-app/api/index.js
	node --check tests/fixtures/js-modules/minimist/index.js

test: lint test-node test-container

test-node:
	NODE_PATH="$(CURDIR)/tests/fixtures/js-modules" node --test tests/download-actual-budget.test.js

check-docker:
	@command -v docker >/dev/null || { echo "docker is not installed or not on PATH"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "docker daemon is not running or the Docker socket is unavailable"; echo "Start Docker Desktop, Colima, or your Docker service, then rerun make test-image."; exit 1; }

test-image: check-docker
	docker build -t $(TEST_BASE_IMAGE) .
	docker build --build-arg BASE_IMAGE=$(TEST_BASE_IMAGE) -f tests/Dockerfile -t $(TEST_IMAGE) .

test-container: check-docker test-image
	DOCKER_IMAGE="$(TEST_IMAGE)" tests/test.sh

clean-test:
	rm -rf tests/.tmp
