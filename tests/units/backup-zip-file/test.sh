#!/bin/bash

TEST_NAME="backup-zip-file"
TEST_OUTPUT_DIR="${OUTPUT_DIR}/${TEST_NAME}"
BACKUP_FILE="${TEST_OUTPUT_DIR}/backup.budget-one.test.zip"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}"
}

function start() {
    docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ACTUAL_BUDGET_URL=https://actual.example.test" \
        -e "ACTUAL_BUDGET_PASSWORD=server-password" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        -e "ACTUAL_BUDGET_E2E_PASSWORD=e2e-password" \
        -e "BACKUP_FILE_SUFFIX=test" \
        "${DOCKER_IMAGE}" \
        backup
}

function test() {
    color blue "Testing..."

    if [[ ! -s "${BACKUP_FILE}" ]]; then
        ((FAILED_NUM++))
        return
    fi

    if ! unzip -p "${BACKUP_FILE}" budget.json | grep -F '"syncId": "budget-one"' >/dev/null; then
        ((FAILED_NUM++))
    fi
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}"

    unset TEST_OUTPUT_DIR
    unset BACKUP_FILE
}

prepare
start
test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
