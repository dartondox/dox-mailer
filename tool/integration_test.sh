#!/bin/sh
# Starts the test servers with Docker and runs the integration tests.
# The servers keep running. Stop them with: docker compose down
set -e
cd "$(dirname "$0")/.."

docker compose up -d --wait

# the sendmail tests use the mailpit program from the image
mkdir -p .dart_tool/integration
docker compose cp mailpit:/mailpit .dart_tool/integration/mailpit

export MAILPIT_SMTP_HOST=localhost
export MAILPIT_BIN="$PWD/.dart_tool/integration/mailpit"
export LOCALSTACK_URL=http://localhost:4566
export MOTO_URL=http://localhost:5050
# the public test token of Postmark: it checks the mail, sends nothing
export POSTMARK_TOKEN=POSTMARK_API_TEST

dart test -t integration "$@"
