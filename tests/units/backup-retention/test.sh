#!/bin/bash

TEST_NAME="backup-retention"
TEST_OUTPUT_DIR="${OUTPUT_DIR}/${TEST_NAME}"

FAILED_NUM=0
RUN_EXIT_CODE=0

color yellow "Starting test case \"${TEST_NAME}\""

function prepare_backup_file() {
    local SYNC_ID="$1"
    local SUFFIX="$2"
    local TIMESTAMP="$3"
    local BACKUP_FILE="${TEST_OUTPUT_DIR}/backup.${SYNC_ID}.${SUFFIX}.zip"

    printf "%s\n" "${BACKUP_FILE}" >"${BACKUP_FILE}"
    touch -t "${TIMESTAMP}" "${BACKUP_FILE}"
}

function prepare() {
    mkdir -p "${TEST_OUTPUT_DIR}"

    prepare_backup_file "budget-one" "20250101" "202501010101"
    prepare_backup_file "budget-one" "20250102" "202501020101"
    prepare_backup_file "budget-one" "20250103" "202501030101"
    prepare_backup_file "budget-one" "20250104" "202501040101"
    prepare_backup_file "budget-one" "20250105" "202501050101"

    prepare_backup_file "budget-two" "20250201" "202502010101"
    prepare_backup_file "budget-two" "20250202" "202502020101"
    prepare_backup_file "budget-two" "20250203" "202502030101"
    prepare_backup_file "budget-two" "20250204" "202502040101"

    printf "not managed by actualbudget-backup\n" >"${TEST_OUTPUT_DIR}/manual-note.txt"
    touch -t "202501010101" "${TEST_OUTPUT_DIR}/manual-note.txt"
}

function start() {
    docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ACTUAL_BUDGET_URL=https://actual.example.test" \
        -e "ACTUAL_BUDGET_PASSWORD=server-password" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        -e "ACTUAL_BUDGET_SYNC_ID_1=budget-two" \
        -e "BACKUP_FILE_SUFFIX=test" \
        -e "BACKUP_KEEP_DAYS=7" \
        -e "BACKUP_KEEP_FILES=3" \
        "${DOCKER_IMAGE}" \
        backup || RUN_EXIT_CODE=$?
}

function assert_file_exists() {
    if [[ ! -f "${TEST_OUTPUT_DIR}/$1" ]]; then
        color red "Expected file to exist: $1"
        ((FAILED_NUM++))
    fi
}

function assert_file_missing() {
    if [[ -f "${TEST_OUTPUT_DIR}/$1" ]]; then
        color red "Expected file to be deleted: $1"
        ((FAILED_NUM++))
    fi
}

function test_retention() {
    color blue "Testing retention..."

    if [[ "${RUN_EXIT_CODE}" -ne 0 ]]; then
        ((FAILED_NUM++))
        return
    fi

    assert_file_exists "backup.budget-one.test.zip"
    assert_file_exists "backup.budget-one.20250105.zip"
    assert_file_exists "backup.budget-one.20250104.zip"
    assert_file_missing "backup.budget-one.20250103.zip"
    assert_file_missing "backup.budget-one.20250102.zip"
    assert_file_missing "backup.budget-one.20250101.zip"

    assert_file_exists "backup.budget-two.test.zip"
    assert_file_exists "backup.budget-two.20250204.zip"
    assert_file_exists "backup.budget-two.20250203.zip"
    assert_file_missing "backup.budget-two.20250202.zip"
    assert_file_missing "backup.budget-two.20250201.zip"

    assert_file_exists "manual-note.txt"
}

function test_invalid_config() {
    local FOUND_MESSAGE_COUNT

    color blue "Testing invalid retention config..."

    FOUND_MESSAGE_COUNT=$(docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        -e "BACKUP_KEEP_FILES=bad" \
        "${DOCKER_IMAGE}" \
        backup 2>&1 | grep -c "BACKUP_KEEP_FILES must be a non-negative integer")

    if [[ "${FOUND_MESSAGE_COUNT}" -ne 1 ]]; then
        ((FAILED_NUM++))
    fi

    FOUND_MESSAGE_COUNT=$(docker run --rm \
        --mount "type=bind,source=${TEST_OUTPUT_DIR},target=${REMOTE_DIR}" \
        -e "RCLONE_REMOTE_DIR=${REMOTE_DIR}" \
        -e "ACTUAL_BUDGET_SYNC_ID=budget-one" \
        -e "BACKUP_KEEP_DAYS=bad" \
        "${DOCKER_IMAGE}" \
        backup 2>&1 | grep -c "BACKUP_KEEP_DAYS must be a non-negative integer")

    if [[ "${FOUND_MESSAGE_COUNT}" -ne 1 ]]; then
        ((FAILED_NUM++))
    fi
}

function cleanup() {
    rm -rf "${TEST_OUTPUT_DIR}"

    unset TEST_OUTPUT_DIR
    unset RUN_EXIT_CODE
}

prepare
start
test_retention
test_invalid_config
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
