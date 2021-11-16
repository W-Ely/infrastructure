#!/bin/sh
# This script runs python linting.
# On creation `chmod +x filename.sh` was ran to make the file executable.

set -eux

if [ "$CONTEXT" = "ci" ]
echo "black:"
then
        black --safe -v --check "$@"
else
        echo " ^v^v^v black ^v^v^v "
        black --safe -v "$@"
fi
echo "pylint:"
pylint "$@"
echo "pycodestyle:"
pycodestyle "$@" \
    --ignore=E203,E402,E711,E712,W503,W405,E231,E501 \
    --max-line-length=88
