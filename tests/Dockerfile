ARG BASE_IMAGE=actualbudget-backup:test-base
FROM ${BASE_IMAGE}

COPY tests/fixtures/source /
COPY tests/fixtures/js-modules /app/node_modules

ENTRYPOINT ["/app/entrypoint.sh"]
