#!/bin/bash

DOCKER_IMAGE="${DOCKER_IMAGE:-actualbudget-backup:test}"
ERROR_NUM=0

TEST_TMP_DIR="$(pwd)/tests/.tmp"
CONFIG_DIR="${TEST_TMP_DIR}/config"
OUTPUT_DIR="${TEST_TMP_DIR}/output"
REMOTE_DIR="/output"

function color() {
    case $1 in
    red) echo -e "\033[31m$2\033[0m" ;;
    green) echo -e "\033[32m$2\033[0m" ;;
    yellow) echo -e "\033[33m$2\033[0m" ;;
    blue) echo -e "\033[34m$2\033[0m" ;;
    none) echo "$2" ;;
    esac
}

function test_result() {
    local SEP="================================================================================"

    if [[ "$2" == "0" ]]; then
        color green "Test case \"$1\" passed"
        color none "${SEP}${SEP}"
        return
    fi

    ((ERROR_NUM++))

    color red "Test case \"$1\" failed"
    color none "${SEP}${SEP}"
}

. tests/units/backup-zip-file/test.sh
. tests/units/backup-retention/test.sh
. tests/units/check-rclone-config-exists/test.sh
. tests/units/check-rclone-flags-valid/test.sh

if [[ "${ERROR_NUM}" == "0" ]]; then
    color green "All tests passed"
else
    color red "Some tests failed"
    exit 1
fi
