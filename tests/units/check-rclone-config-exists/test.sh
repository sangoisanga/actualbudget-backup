#!/bin/bash

TEST_NAME="check-rclone-config-exists"
TEST_OUTPUT_DIR="$(pwd)/${OUTPUT_DIR}/${TEST_NAME}"
TEST_CONFIG_DIR="$(pwd)/${CONFIG_DIR}/${TEST_NAME}"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}" "${TEST_CONFIG_DIR}"
}

function test() {
    color blue "Testing..."

    FOUND_MESSAGE_COUNT=$(docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        --mount "type=bind,source=${TEST_CONFIG_DIR},target=/config" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        "${DOCKER_IMAGE}" \
        backup | grep -c "rclone configuration information not found")

    if [[ "${FOUND_MESSAGE_COUNT}" -ne 1 ]]; then
        ((FAILED_NUM++))
    fi
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}" "${TEST_CONFIG_DIR}"

    unset TEST_OUTPUT_DIR
    unset TEST_CONFIG_DIR
    unset FOUND_MESSAGE_COUNT
}

prepare
test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
