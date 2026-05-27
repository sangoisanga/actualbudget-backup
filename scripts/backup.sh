#!/bin/bash

# shellcheck source=scripts/includes.sh
. /app/includes.sh

function clear_dir() {
    rm -rf backup
}

function backup_file_name() {
    # backup zip file
    BACKUP_FILE_ZIP="backup/backup.$1.${NOW}.zip"
    color blue "file name \"${BACKUP_FILE_ZIP}\""
}

function download_actual_budget() {
    color blue "Downloading Actual Budget backup using @actual-app/api"

    # Parameters:
    API_VERSION=${ACTUAL_API_VERSION:-latest}
    API_DOWNLOAD_PATH=${ACTUAL_API_DOWNLOAD_PATH:-/tmp/actual-download}

    # Clean and prepare folders
    mkdir -p "${API_DOWNLOAD_PATH}"
    mkdir -p "backup"

    color green "Installing @actual-app/api@$API_VERSION (if needed)..."
    if ! [ -d "/app/node_modules/@actual-app/api" ]; then
        echo "Installing @actual-app/api@$API_VERSION..."
        if ! npm install --prefix /app "@actual-app/api@$API_VERSION" --unsafe-perm; then
            color red "install @actual-app/api failed"
            return 1
        fi
    else
        color green "@actual-app/api@$API_VERSION already installed."
    fi

    # Convert arrays to comma-separated strings
    SYNC_IDS="$(
        IFS=,
        echo "${ACTUAL_BUDGET_SYNC_ID_LIST[*]}"
    )"
    E2E_PASSWORDS="$(
        IFS=,
        echo "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[*]}"
    )"

    export NODE_PATH=/app/node_modules

    # Run Node with arguments instead of relying on environment variable export
    if ! node "/app/download-actual-budget.js" \
        --syncIds="$SYNC_IDS" \
        --e2ePasswords="$E2E_PASSWORDS" \
        --dataDir="$API_DOWNLOAD_PATH" \
        --destDir="$(pwd)/backup" \
        --serverURL="$ACTUAL_BUDGET_URL" \
        --password="$ACTUAL_BUDGET_PASSWORD" \
        --now="$NOW"; then
        color red "download actual budget failed"
        return 1
    fi

    return 0
}

function backup() {
    mkdir -p "backup"

    download_actual_budget || return 1

    ls -lah "backup"

    return 0
}

function upload() {
    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"; do
        backup_file_name "${ACTUAL_BUDGET_SYNC_ID_X}"
        if ! file "${BACKUP_FILE_ZIP}" | grep -q "data"; then
            color red "File not found \"${BACKUP_FILE_ZIP}\""
            color red "Nothing has been backed up!"
            return 1
        fi
    done

    # upload
    local HAS_ERROR="FALSE"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"; do
        for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"; do
            backup_file_name "${ACTUAL_BUDGET_SYNC_ID_X}"
            color blue "upload backup file to storage system $(color yellow "[${BACKUP_FILE_ZIP} -> ${RCLONE_REMOTE_X}]")"

            # shellcheck disable=SC2086
            if ! rclone ${RCLONE_GLOBAL_FLAG} copy "${BACKUP_FILE_ZIP}" "${RCLONE_REMOTE_X}"; then
                color red "upload failed"
                HAS_ERROR="TRUE"
            fi
        done
    done

    if [[ "${HAS_ERROR}" == "TRUE" ]]; then
        return 1
    fi

    return 0
}

function list_backup_files() {
    local RCLONE_REMOTE_X="$1"
    local ACTUAL_BUDGET_SYNC_ID_X="$2"
    local MIN_AGE="${3:-}"
    local BACKUP_FILE_PREFIX="backup.${ACTUAL_BUDGET_SYNC_ID_X}."
    local RCLONE_LIST_JSON
    local RCLONE_LSJSON_ARGS=("--files-only")

    if [[ -n "${MIN_AGE}" ]]; then
        RCLONE_LSJSON_ARGS=("${RCLONE_LSJSON_ARGS[@]}" "--min-age" "${MIN_AGE}")
    fi

    # shellcheck disable=SC2086
    if ! RCLONE_LIST_JSON="$(rclone ${RCLONE_GLOBAL_FLAG} lsjson "${RCLONE_REMOTE_X}" "${RCLONE_LSJSON_ARGS[@]}")"; then
        color red "list backup files failed $(color yellow "[${RCLONE_REMOTE_X}]")"
        return 1
    fi

    jq -r \
        --arg prefix "${BACKUP_FILE_PREFIX}" \
        'sort_by(.ModTime) | reverse | .[] | select(.Path | startswith($prefix) and endswith(".zip")) | .Path' \
        <<<"${RCLONE_LIST_JSON}"
}

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"; do
            for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"; do
                color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}/${ACTUAL_BUDGET_SYNC_ID_X}]")"

                local RCLONE_PROTECTED_FILE
                local RCLONE_KEEP_FILE
                local RCLONE_KEEP_OUTPUT=""
                local RCLONE_DELETE_FILE
                local RCLONE_DELETE_OUTPUT=""
                local RCLONE_KEEP_LIST=()
                local RCLONE_DELETE_LIST=()
                declare -A RCLONE_PROTECTED_FILE_MAP=()

                if [[ "${BACKUP_KEEP_FILES}" -gt 0 ]]; then
                    if ! RCLONE_KEEP_OUTPUT="$(list_backup_files "${RCLONE_REMOTE_X}" "${ACTUAL_BUDGET_SYNC_ID_X}")"; then
                        continue
                    fi

                    if [[ -n "${RCLONE_KEEP_OUTPUT}" ]]; then
                        mapfile -t RCLONE_KEEP_LIST <<<"${RCLONE_KEEP_OUTPUT}"
                    fi

                    for RCLONE_KEEP_FILE in "${RCLONE_KEEP_LIST[@]:0:${BACKUP_KEEP_FILES}}"; do
                        RCLONE_PROTECTED_FILE_MAP["${RCLONE_KEEP_FILE}"]=1
                    done
                fi

                if ! RCLONE_DELETE_OUTPUT="$(list_backup_files "${RCLONE_REMOTE_X}" "${ACTUAL_BUDGET_SYNC_ID_X}" "${BACKUP_KEEP_DAYS}d")"; then
                    continue
                fi

                if [[ -n "${RCLONE_DELETE_OUTPUT}" ]]; then
                    mapfile -t RCLONE_DELETE_LIST <<<"${RCLONE_DELETE_OUTPUT}"
                fi

                for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"; do
                    if [[ -n "${RCLONE_PROTECTED_FILE_MAP[${RCLONE_DELETE_FILE}]:-}" ]]; then
                        color yellow "keeping \"${RCLONE_DELETE_FILE}\" because BACKUP_KEEP_FILES=${BACKUP_KEEP_FILES}"
                        continue
                    fi

                    color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                    # shellcheck disable=SC2086
                    if ! rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"; then
                        color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                    fi
                done

                for RCLONE_PROTECTED_FILE in "${!RCLONE_PROTECTED_FILE_MAP[@]}"; do
                    unset "RCLONE_PROTECTED_FILE_MAP[${RCLONE_PROTECTED_FILE}]"
                done
            done
        done
    fi
}

color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

function run_backup() {
    init_env || return 1

    send_notification "start" "Start backup at $(date +"%Y-%m-%d %H:%M:%S %Z")."

    NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"

    check_rclone_connection any || return 1

    clear_dir || return 1
    backup || return 1
    upload || return 1
    BACKUP_FILE_COUNT="$(find backup -type f -name '*.zip' 2>/dev/null | wc -l | tr -d ' ')"
    clear_dir || return 1
    clear_history

    return 0
}

BACKUP_FILE_COUNT=0
START_TIME="$(date +%s)"

run_backup
EXIT_CODE=$?
DURATION_SECONDS=$(($(date +%s) - START_TIME))

if [[ "${EXIT_CODE}" -eq 0 ]]; then
    send_notification "success" "Backup completed successfully at $(date +"%Y-%m-%d %H:%M:%S %Z"). Files: ${BACKUP_FILE_COUNT}; Duration: ${DURATION_SECONDS}s."
else
    send_notification "failure" "Backup failed at $(date +"%Y-%m-%d %H:%M:%S %Z"). Exit code: ${EXIT_CODE}; Duration: ${DURATION_SECONDS}s."
fi

color none ""
exit "${EXIT_CODE}"
