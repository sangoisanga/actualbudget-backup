#!/bin/bash

# shellcheck disable=SC2034,SC2086,SC2181,SC1090,SC2206,SC2153,SC2012

ENV_FILE="/.env"
CRON_CONFIG_FILE="${HOME}/crontabs"

#################### Function ####################
########################################
# Print colorful message.
# Arguments:
#     color
#     message
# Outputs:
#     colorful message
########################################
function color() {
    case $1 in
    red) echo -e "\033[31m$2\033[0m" ;;
    green) echo -e "\033[32m$2\033[0m" ;;
    yellow) echo -e "\033[33m$2\033[0m" ;;
    blue) echo -e "\033[34m$2\033[0m" ;;
    none) echo "$2" ;;
    esac
}

########################################
# Check storage system connection success.
# Arguments:
#     None
########################################
function check_rclone_connection() {
    # check configuration exist
    local RCLONE_CONFIG_FILE
    RCLONE_CONFIG_FILE=$(rclone config file 2>&1 | grep -o '/[^[:space:]]*rclone\.conf')
    grep -c "\[${RCLONE_REMOTE_NAME}\]" "${RCLONE_CONFIG_FILE}" >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        color red "rclone configuration information not found"
        color blue "Please configure rclone first, check https://github.com/rodriguestiago0/actualbudget-backup#configure-rclone-%EF%B8%8F-must-read-%EF%B8%8F"
        return 1
    fi

    # check flags validity
    rclone ${RCLONE_GLOBAL_FLAG} version >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        color red "illegal rclone global flags"
        color blue "Please check https://rclone.org/flags/"
        return 1
    fi

    # check connection
    local ERROR_COUNT=0

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"; do
        rclone ${RCLONE_GLOBAL_FLAG} lsd "${RCLONE_REMOTE_X}" >/dev/null
        if [[ $? != 0 ]]; then
            color red "storage system connection may not be initialized, try initializing $(color yellow "[${RCLONE_REMOTE_X}]")"

            rclone ${RCLONE_GLOBAL_FLAG} mkdir "${RCLONE_REMOTE_X}"
            if [[ $? != 0 ]]; then
                color red "storage system connection failure $(color yellow "[${RCLONE_REMOTE_X}]")"

                ((ERROR_COUNT++))
            fi
        fi
    done

    if [[ "${ERROR_COUNT}" -gt 0 ]]; then
        if [[ "$1" == "all" ]]; then
            color red "storage system connection failure exists"
            return 1
        elif [[ "$1" == "any" ]]; then
            if [[ "${ERROR_COUNT}" -eq "${#RCLONE_REMOTE_LIST[@]}" ]]; then
                color red "all storage system connections failed"
                return 1
            else
                color yellow "some storage system connections failed, but the backup will continue"
            fi
        fi
    fi

    return 0
}

########################################
# Check file is exist.
# Arguments:
#     file
########################################
function check_file_exist() {
    if [[ ! -f "$1" ]]; then
        color red "cannot access $1: No such file"
        exit 1
    fi
}

########################################
# Check directory is exist.
# Arguments:
#     directory
########################################
function check_dir_exist() {
    if [[ ! -d "$1" ]]; then
        color red "cannot access $1: No such directory"
        exit 1
    fi
}

########################################
# Send notification by Telegram.
# Arguments:
#     status (start / success / failure)
#     notification subject
#     notification content
########################################
function send_telegram() {
    local STATUS="$1"
    local SUBJECT="$2"
    local CONTENT="$3"

    if [[ "${TELEGRAM_ENABLE}" != "TRUE" ]]; then
        return 0
    fi

    case "${STATUS}" in
    start) [[ "${TELEGRAM_WHEN_START}" == "TRUE" ]] || return 0 ;;
    success) [[ "${TELEGRAM_WHEN_SUCCESS}" == "TRUE" ]] || return 0 ;;
    failure) [[ "${TELEGRAM_WHEN_FAILURE}" == "TRUE" ]] || return 0 ;;
    *)
        color red "unsupported telegram notification status, only supports start, success, failure"
        return 0
        ;;
    esac

    local DISABLE_NOTIFICATION="false"
    if [[ "${TELEGRAM_DISABLE_NOTIFICATION}" == "TRUE" ]]; then
        DISABLE_NOTIFICATION="true"
    fi

    local TEXT="${SUBJECT}

${CONTENT}"
    local PAYLOAD
    PAYLOAD="$(jq -n \
        --arg chat_id "${TELEGRAM_CHAT_ID}" \
        --arg text "${TEXT}" \
        --arg parse_mode "${TELEGRAM_PARSE_MODE}" \
        --arg message_thread_id "${TELEGRAM_MESSAGE_THREAD_ID}" \
        --argjson disable_notification "${DISABLE_NOTIFICATION}" \
        '{
            chat_id: $chat_id,
            text: $text,
            disable_notification: $disable_notification
        }
        + (if $parse_mode != "" then { parse_mode: $parse_mode } else {} end)
        + (if $message_thread_id != "" then { message_thread_id: ($message_thread_id | tonumber) } else {} end)')"
    if [[ $? != 0 ]]; then
        color red "${STATUS} telegram payload creation has failed"
        return 0
    fi

    curl --fail --silent --show-error --max-time 15 --retry 3 --retry-delay 1 \
        -o /dev/null \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    if [[ $? != 0 ]]; then
        color red "${STATUS} telegram sending has failed"
    else
        color blue "${STATUS} telegram has been sent successfully"
    fi
}

########################################
# Send notification.
# Arguments:
#     status (start / success / failure)
#     notification content
########################################
function send_notification() {
    local SUBJECT_START="${DISPLAY_NAME} Backup Start"
    local SUBJECT_SUCCESS="${DISPLAY_NAME} Backup Success"
    local SUBJECT_FAILURE="${DISPLAY_NAME} Backup Failed"

    case "$1" in
    start)
        send_telegram "start" "${SUBJECT_START}" "$2"
        ;;
    success)
        send_telegram "success" "${SUBJECT_SUCCESS}" "$2"
        ;;
    failure)
        send_telegram "failure" "${SUBJECT_FAILURE}" "$2"
        ;;
    *)
        color red "unsupported notification status, only supports start, success, failure"
        ;;
    esac
}

########################################
# Export variables from .env file.
# Arguments:
#     None
# Outputs:
#     variables with prefix 'DOTENV_'
# Reference:
#     https://gist.github.com/judy2k/7656bfe3b322d669ef75364a46327836#gistcomment-3632918
########################################
function export_env_file() {
    if [[ -f "${ENV_FILE}" ]]; then
        color blue "find \"${ENV_FILE}\" file and export variables"
        set -a
        source <(cat "${ENV_FILE}" | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/DOTENV_\1=\2/')
        set +a
    fi
}

########################################
# Get variables from
#     environment variables,
#     secret file in environment variables,
#     secret file in .env file,
#     environment variables in .env file.
# Arguments:
#     variable name
# Outputs:
#     variable value
########################################
function get_env() {
    local VAR="$1"
    local VAR_FILE="${VAR}_FILE"
    local VAR_DOTENV="DOTENV_${VAR}"
    local VAR_DOTENV_FILE="DOTENV_${VAR_FILE}"
    local VALUE=""

    if [[ -n "${!VAR:-}" ]]; then
        VALUE="${!VAR}"
    elif [[ -n "${!VAR_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_FILE}")"
    elif [[ -n "${!VAR_DOTENV_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_DOTENV_FILE}")"
    elif [[ -n "${!VAR_DOTENV:-}" ]]; then
        VALUE="${!VAR_DOTENV}"
    fi

    export "${VAR}=${VALUE}"
}

########################################
# Get RCLONE_REMOTE_LIST variables.
# Arguments:
#     None
# Outputs:
#     variable value
########################################
function get_rclone_remote_list() {
    # RCLONE_REMOTE_LIST
    RCLONE_REMOTE_LIST=()

    local i=0
    local RCLONE_REMOTE_NAME_X_REFER
    local RCLONE_REMOTE_DIR_X_REFER
    local RCLONE_REMOTE_X

    # for multiple
    while true; do
        RCLONE_REMOTE_NAME_X_REFER="RCLONE_REMOTE_NAME_${i}"
        RCLONE_REMOTE_DIR_X_REFER="RCLONE_REMOTE_DIR_${i}"
        get_env "${RCLONE_REMOTE_NAME_X_REFER}"
        get_env "${RCLONE_REMOTE_DIR_X_REFER}"

        if [[ -z "${!RCLONE_REMOTE_NAME_X_REFER}" || -z "${!RCLONE_REMOTE_DIR_X_REFER}" ]]; then
            break
        fi

        RCLONE_REMOTE_X=$(echo "${!RCLONE_REMOTE_NAME_X_REFER}:${!RCLONE_REMOTE_DIR_X_REFER}" | sed 's@\(/*\)$@@')
        RCLONE_REMOTE_LIST=(${RCLONE_REMOTE_LIST[@]} "${RCLONE_REMOTE_X}")

        ((i++))
    done
}

function init_env_display() {
    get_env DISPLAY_NAME
    DISPLAY_NAME="${DISPLAY_NAME:-"Actual Budget"}"
}

function init_env_telegram() {
    get_env TELEGRAM_BOT_TOKEN
    get_env TELEGRAM_CHAT_ID
    get_env TELEGRAM_MESSAGE_THREAD_ID
    get_env TELEGRAM_PARSE_MODE

    get_env TELEGRAM_DISABLE_NOTIFICATION
    if [[ "$(echo "${TELEGRAM_DISABLE_NOTIFICATION}" | tr '[:lower:]' '[:upper:]')" == "TRUE" ]]; then
        TELEGRAM_DISABLE_NOTIFICATION="TRUE"
    else
        TELEGRAM_DISABLE_NOTIFICATION="FALSE"
    fi

    get_env TELEGRAM_WHEN_START
    if [[ "$(echo "${TELEGRAM_WHEN_START}" | tr '[:lower:]' '[:upper:]')" == "FALSE" ]]; then
        TELEGRAM_WHEN_START="FALSE"
    else
        TELEGRAM_WHEN_START="TRUE"
    fi

    get_env TELEGRAM_WHEN_SUCCESS
    if [[ "$(echo "${TELEGRAM_WHEN_SUCCESS}" | tr '[:lower:]' '[:upper:]')" == "FALSE" ]]; then
        TELEGRAM_WHEN_SUCCESS="FALSE"
    else
        TELEGRAM_WHEN_SUCCESS="TRUE"
    fi

    get_env TELEGRAM_WHEN_FAILURE
    if [[ "$(echo "${TELEGRAM_WHEN_FAILURE}" | tr '[:lower:]' '[:upper:]')" == "FALSE" ]]; then
        TELEGRAM_WHEN_FAILURE="FALSE"
    else
        TELEGRAM_WHEN_FAILURE="TRUE"
    fi

    if [[ -n "${TELEGRAM_MESSAGE_THREAD_ID}" && ! "${TELEGRAM_MESSAGE_THREAD_ID}" =~ ^[0-9]+$ ]]; then
        color yellow "TELEGRAM_MESSAGE_THREAD_ID is invalid, ignoring"
        TELEGRAM_MESSAGE_THREAD_ID=""
    fi

    if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
        TELEGRAM_ENABLE="TRUE"
    else
        TELEGRAM_ENABLE="FALSE"
    fi
}

function init_actual_sync_list() {
    ACTUAL_BUDGET_SYNC_ID_LIST=()

    local i=0
    local ACTUAL_BUDGET_SYNC_ID_X_REFER

    # for multiple
    while true; do
        ACTUAL_BUDGET_SYNC_ID_X_REFER="ACTUAL_BUDGET_SYNC_ID_${i}"
        get_env "${ACTUAL_BUDGET_SYNC_ID_X_REFER}"

        if [[ -z "${!ACTUAL_BUDGET_SYNC_ID_X_REFER}" ]]; then
            break
        fi

        ACTUAL_BUDGET_SYNC_ID_LIST=(${ACTUAL_BUDGET_SYNC_ID_LIST[@]} ${!ACTUAL_BUDGET_SYNC_ID_X_REFER})

        ((i++))
    done

    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"; do
        color yellow "ACTUAL_BUDGET_SYNC_ID: ${ACTUAL_BUDGET_SYNC_ID_X}"
    done
}

function init_actual_e2e_list() {
    ACTUAL_BUDGET_E2E_PASSWORD_LIST=()

    local i=0
    local ACTUAL_BUDGET_E2E_PASSWORD_X_REFER

    # for multiple
    while true; do
        ACTUAL_BUDGET_E2E_PASSWORD_X_REFER="ACTUAL_BUDGET_E2E_PASSWORD_${i}"
        get_env "${ACTUAL_BUDGET_E2E_PASSWORD_X_REFER}"

        if [[ -z "${!ACTUAL_BUDGET_E2E_PASSWORD_X_REFER}" ]]; then
            break
        fi

        ACTUAL_BUDGET_E2E_PASSWORD_LIST=(${ACTUAL_BUDGET_E2E_PASSWORD_LIST[@]} ${!ACTUAL_BUDGET_E2E_PASSWORD_X_REFER})

        ((i++))
    done

    for ACTUAL_BUDGET_E2E_PASSWORD_X in "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[@]}"; do
        color yellow "ACTUAL_BUDGET_E2E_PASSWORD: *****"
    done
}

function init_actual_env() {
    # ACTUAL BUDGET
    get_env ACTUAL_BUDGET_URL
    ACTUAL_BUDGET_URL="${ACTUAL_BUDGET_URL:-"https://localhost:5006"}"
    color yellow "ACTUAL_BUDGET_URL: ${ACTUAL_BUDGET_URL}"

    get_env ACTUAL_BUDGET_PASSWORD
    ACTUAL_BUDGET_PASSWORD="${ACTUAL_BUDGET_PASSWORD:-""}"
    color yellow "ACTUAL_BUDGET_PASSWORD: *****"

    get_env ACTUAL_BUDGET_SYNC_ID

    if [[ -z "${ACTUAL_BUDGET_SYNC_ID}" ]]; then
        color red "Invalid sync id"
        return 1
    fi

    ACTUAL_BUDGET_SYNC_ID_0="${ACTUAL_BUDGET_SYNC_ID}"

    init_actual_sync_list

    get_env ACTUAL_BUDGET_E2E_PASSWORD
    ACTUAL_BUDGET_E2E_PASSWORD_0="${ACTUAL_BUDGET_E2E_PASSWORD}"

    init_actual_e2e_list

    return 0
}

########################################
# Initialization environment variables.
# Arguments:
#     None
# Outputs:
#     environment variables
########################################
function init_env() {
    # export
    export_env_file

    init_env_display
    init_env_telegram

    # CRON
    get_env CRON
    CRON="${CRON:-"0 0 * * *"}"

    # RCLONE_REMOTE_NAME
    get_env RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-"ActualBudgetBackup"}"
    RCLONE_REMOTE_NAME_0="${RCLONE_REMOTE_NAME}"

    # RCLONE_REMOTE_DIR
    get_env RCLONE_REMOTE_DIR
    RCLONE_REMOTE_DIR="${RCLONE_REMOTE_DIR:-"/ActualBudgetBackup/"}"
    RCLONE_REMOTE_DIR_0="${RCLONE_REMOTE_DIR}"

    # get RCLONE_REMOTE_LIST
    get_rclone_remote_list

    # RCLONE_GLOBAL_FLAG
    get_env RCLONE_GLOBAL_FLAG
    RCLONE_GLOBAL_FLAG="${RCLONE_GLOBAL_FLAG:-""}"

    # BACKUP_KEEP_DAYS
    get_env BACKUP_KEEP_DAYS
    BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-"0"}"

    # BACKUP_FILE_DATE_FORMAT
    get_env BACKUP_FILE_SUFFIX
    get_env BACKUP_FILE_DATE
    get_env BACKUP_FILE_DATE_SUFFIX
    BACKUP_FILE_DATE="$(echo "${BACKUP_FILE_DATE:-"%Y%m%d"}${BACKUP_FILE_DATE_SUFFIX}" | sed 's/[^0-9a-zA-Z%_-]//g')"
    BACKUP_FILE_DATE_FORMAT="$(echo "${BACKUP_FILE_SUFFIX:-"${BACKUP_FILE_DATE}"}" | sed 's/\///g')"

    # TIMEZONE
    get_env TIMEZONE
    local TIMEZONE_MATCHED_COUNT
    TIMEZONE_MATCHED_COUNT=$(ls "/usr/share/zoneinfo/${TIMEZONE}" 2>/dev/null | wc -l)
    if [[ "${TIMEZONE_MATCHED_COUNT}" -ne 1 ]]; then
        TIMEZONE="UTC"
    fi

    init_actual_env || return 1

    color yellow "========================================"
    color yellow "CRON: ${CRON}"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"; do
        color yellow "RCLONE_REMOTE: ${RCLONE_REMOTE_X}"
    done

    color yellow "RCLONE_GLOBAL_FLAG: ${RCLONE_GLOBAL_FLAG}"
    color yellow "BACKUP_FILE_DATE_FORMAT: ${BACKUP_FILE_DATE_FORMAT} (example \"[filename].$(date +"${BACKUP_FILE_DATE_FORMAT}").zip\")"
    color yellow "BACKUP_KEEP_DAYS: ${BACKUP_KEEP_DAYS}"

    color yellow "TIMEZONE: ${TIMEZONE}"
    color yellow "DISPLAY_NAME: ${DISPLAY_NAME}"
    color yellow "TELEGRAM_ENABLE: ${TELEGRAM_ENABLE}"
    color yellow "TELEGRAM_WHEN_START: ${TELEGRAM_WHEN_START}"
    color yellow "TELEGRAM_WHEN_SUCCESS: ${TELEGRAM_WHEN_SUCCESS}"
    color yellow "TELEGRAM_WHEN_FAILURE: ${TELEGRAM_WHEN_FAILURE}"
    color yellow "========================================"

    return 0
}
