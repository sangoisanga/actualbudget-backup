#!/bin/bash

TEST_NAME="telegram-notification"

FAILED_NUM=0

color yellow "Starting test case \"${TEST_NAME}\""

function capture_disable_notification() {
    local STATUS="$1"

    docker run --rm \
        --entrypoint bash \
        -e "TELEGRAM_BOT_TOKEN=test-token" \
        -e "TELEGRAM_CHAT_ID=12345" \
        "${DOCKER_IMAGE}" \
        -c '
            STATUS="$1"

            . /app/includes.sh
            init_env_telegram

            function curl() {
                while [[ "$#" -gt 0 ]]; do
                    if [[ "$1" == "-d" ]]; then
                        echo "$2" >/tmp/telegram-payload.json
                        shift
                    fi

                    shift || true
                done

                echo "{\"ok\":true}"
                echo "200"
            }

            send_telegram "${STATUS}" "Subject" "Content"
            jq -r ".disable_notification" /tmp/telegram-payload.json
        ' \
        bash "${STATUS}" | grep -E "^(true|false)$"
}

function capture_telegram_failure() {
    docker run --rm \
        --entrypoint bash \
        -e "TELEGRAM_BOT_TOKEN=test-token" \
        -e "TELEGRAM_CHAT_ID=12345" \
        "${DOCKER_IMAGE}" \
        -c '
            . /app/includes.sh
            init_env_telegram

            function curl() {
                echo "{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: chat not found\"}"
                echo "400"
            }

            send_telegram "failure" "Subject" "Content"
        '
}

function assert_disable_notification() {
    local STATUS="$1"
    local EXPECTED="$2"

    local ACTUAL
    ACTUAL="$(capture_disable_notification "${STATUS}")"

    if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
        color red "Expected ${STATUS} disable_notification to be ${EXPECTED}, got ${ACTUAL}"
        ((FAILED_NUM++))
    fi
}

function assert_contains() {
    local OUTPUT="$1"
    local EXPECTED="$2"

    if [[ "${OUTPUT}" != *"${EXPECTED}"* ]]; then
        color red "Expected output to contain ${EXPECTED}"
        ((FAILED_NUM++))
    fi
}

function test() {
    color blue "Testing..."

    assert_disable_notification "start" "true"
    assert_disable_notification "success" "true"
    assert_disable_notification "failure" "false"

    local FAILURE_OUTPUT
    FAILURE_OUTPUT="$(capture_telegram_failure)"
    assert_contains "${FAILURE_OUTPUT}" "failure telegram sending has failed"
    assert_contains "${FAILURE_OUTPUT}" "telegram HTTP status: 400"
    assert_contains "${FAILURE_OUTPUT}" "telegram response: {\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: chat not found\"}"
}

function cleanup() {
    return 0
}

test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
