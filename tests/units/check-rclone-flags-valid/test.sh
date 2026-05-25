#!/bin/bash

TEST_NAME="check-rclone-flags-valid"
TEST_OUTPUT_DIR="${OUTPUT_DIR}/${TEST_NAME}"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}"
}

function test() {
    color blue "Testing..."

    FOUND_MESSAGE_COUNT=$(docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "RCLONE_GLOBAL_FLAG=-v --non-existent" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        "${DOCKER_IMAGE}" \
        backup | grep -c "illegal rclone global flags")

    if [[ "${FOUND_MESSAGE_COUNT}" -ne 1 ]]; then
        ((FAILED_NUM++))
    fi
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}"

    unset TEST_OUTPUT_DIR
    unset FOUND_MESSAGE_COUNT
}

prepare
test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
