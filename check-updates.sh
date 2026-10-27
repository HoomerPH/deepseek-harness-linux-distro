#!/usr/bin/env bash
# Thin wrapper: check whether a newer upstream release exists.
# Exit code 0 = up to date, 1 = update available, 2 = error.
exec "$(dirname "$(readlink -f "$0")")/update-package.sh" --check "$@"
