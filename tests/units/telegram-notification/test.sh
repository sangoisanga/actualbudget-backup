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
                local PAYLOAD=""

                while [[ "$#" -gt 0 ]]; do
                    if [[ "$1" == "-d" ]]; then
                        PAYLOAD="$2"
                        shift
                    fi

                    shift || true
                done

                jq -r ".disable_notification" <<<"${PAYLOAD}"
            }

            send_telegram "${STATUS}" "Subject" "Content"
        ' \
        bash "${STATUS}" | grep -E "^(true|false)$"
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

function test() {
    color blue "Testing..."

    assert_disable_notification "start" "true"
    assert_disable_notification "success" "true"
    assert_disable_notification "failure" "false"
}

function cleanup() {
    return 0
}

test
cleanup

test_result "${TEST_NAME}" "${FAILED_NUM}"
