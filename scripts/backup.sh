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

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"; do
            color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}]")"

            # shellcheck disable=SC2086
            mapfile -t RCLONE_DELETE_LIST < <(rclone ${RCLONE_GLOBAL_FLAG} lsf "${RCLONE_REMOTE_X}" --min-age "${BACKUP_KEEP_DAYS}d")

            for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"; do
                color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                # shellcheck disable=SC2086
                if ! rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"; then
                    color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                fi
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
