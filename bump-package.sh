#!/usr/bin/env bash
# Thin wrapper: bump PKGBUILD/_SRCINFO to the newest upstream release.
# Pass --build to rebuild and smoke-test afterwards, --dry-run to preview.
exec "$(dirname "$(readlink -f "$0")")/update-package.sh" --bump "$@"
