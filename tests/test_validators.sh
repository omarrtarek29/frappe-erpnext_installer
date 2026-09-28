#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/installer/validators.sh"

failures=0

expect_ok() {
	local name="$1"
	shift
	if "$@"; then
		return 0
	fi
	echo "FAIL $name"
	failures=$((failures + 1))
}

expect_fail() {
	local name="$1"
	shift
	if "$@"; then
		echo "FAIL $name"
		failures=$((failures + 1))
	fi
}

expect_ok "10.3 < 10.6" version_lt "10.3" "10.6"
expect_fail "11.8 < 11.8" version_lt "11.8" "11.8"

if [ "$(distro_mariadb_version 26.04)" != "11.8" ]; then
	echo "FAIL ubuntu 26.04 mariadb"
	failures=$((failures + 1))
fi
if [ "$(distro_mariadb_version 24.04)" != "10.11" ]; then
	echo "FAIL ubuntu 24.04 mariadb"
	failures=$((failures + 1))
fi
if version_lt "$(distro_mariadb_version 26.04)" "11.8"; then
	echo "FAIL 26.04 should satisfy MariaDB 11.8"
	failures=$((failures + 1))
fi
if ! version_lt "$(distro_mariadb_version 24.04)" "11.8"; then
	echo "FAIL 24.04 MariaDB should be older than 11.8"
	failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi

echo "validator tests passed"
