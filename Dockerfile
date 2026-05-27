# syntax=docker/dockerfile:1

FROM rclone/rclone:1.74.1

LABEL "org.opencontainers.image.title"="Actual Budget Backup" \
  "org.opencontainers.image.description"="Docker image for backing up Actual Budget data to rclone remotes" \
  "org.opencontainers.image.source"="https://github.com/sangoisanga/actualbudget-backup" \
  "org.opencontainers.image.url"="https://github.com/sangoisanga/actualbudget-backup" \
  "org.opencontainers.image.licenses"="MIT" \
  "repository"="https://github.com/sangoisanga/actualbudget-backup" \
  "homepage"="https://github.com/sangoisanga/actualbudget-backup"

ARG USER_NAME="backuptool"
ARG USER_ID="1100"

ENV LOCALTIME_FILE="/tmp/localtime"

COPY scripts/*.js /app/
COPY scripts/*.sh /app/

RUN chmod +x /app/* \
  && apk add --no-cache grep file bash supercronic curl jq zip nodejs npm wget tar xz \
  && ln -sf "${LOCALTIME_FILE}" /etc/localtime \
  && addgroup -g "${USER_ID}" "${USER_NAME}" \
  && adduser -u "${USER_ID}" -Ds /bin/sh -G "${USER_NAME}" "${USER_NAME}"

ENTRYPOINT ["/app/entrypoint.sh"]
