#!/bin/sh
# A sendmail for the integration tests: the sendmail of Mailpit. It sends
# to the Mailpit server at MAILPIT_SENDMAIL_SMTP.
exec "${MAILPIT_BIN:-mailpit}" sendmail -S "${MAILPIT_SENDMAIL_SMTP:-localhost:1025}" "$@"
