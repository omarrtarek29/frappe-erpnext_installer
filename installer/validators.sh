#!/usr/bin/env bash

# Checks for wizard and config-file input. Return 0 on success, 1 on failure.

validate_linux_user() {
	local value="${1:-}"
	[[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate_bench_name() {
	local value="${1:-}"
	[[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && [[ "$value" != *..* ]]
}

validate_site_name() {
	local value="${1:-}"
	[[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,62})(\.[A-Za-z0-9]([A-Za-z0-9-]{0,62}))*$ ]]
}

validate_optional_domain() {
	local value="${1:-}"
	[ -z "$value" ] && return 0
	validate_site_name "$value"
}

validate_choice() {
	local value="${1:-}"
	[[ "$value" == "yes" || "$value" == "no" ]]
}

validate_password_value() {
	local value="${1:-}"
	[ -n "$value" ] || return 1
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

validate_optional_email() {
	local value="${1:-}"
	[ -z "$value" ] && return 0
	[[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

sql_escape_string() {
	printf "%s" "$1" | sed "s/'/''/g"
}

# Read the server version from `mariadb --version`, ignoring the client library version.
mariadb_version_from_text() {
	local raw="${1:-}"
	local found=""

	# Ubuntu packages lead with the client library ("Ver 15.1") and put the
	# server release after "Distrib". Official MariaDB builds use "11.8.2-MariaDB".
	found="$(printf '%s\n' "$raw" | grep -oE 'Distrib [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
	if [ -z "$found" ]; then
		found="$(printf '%s\n' "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?-MariaDB' | head -1 | grep -oE '^[0-9]+\.[0-9]+' || true)"
	fi
	printf '%s\n' "$found"
}

# MariaDB version shipped by each supported Ubuntu release.
distro_mariadb_version() {
	case "${1:-}" in
		26.04) printf '%s\n' "11.8" ;;
		24.04) printf '%s\n' "10.11" ;;
		22.04) printf '%s\n' "10.6" ;;
		20.04) printf '%s\n' "10.3" ;;
		*) printf '%s\n' "" ;;
	esac
}

# Return 0 when major.minor A is older than major.minor B.
version_lt() {
	local left="${1:-0}" right="${2:-0}"
	local left_major left_minor right_major right_minor

	left_major="${left%%.*}"
	left_minor="${left#*.}"
	left_minor="${left_minor%%.*}"
	right_major="${right%%.*}"
	right_minor="${right#*.}"
	right_minor="${right_minor%%.*}"

	left_major="${left_major:-0}"
	left_minor="${left_minor:-0}"
	right_major="${right_major:-0}"
	right_minor="${right_minor:-0}"

	if [ "$left_major" -lt "$right_major" ]; then
		return 0
	fi
	if [ "$left_major" -eq "$right_major" ] && [ "$left_minor" -lt "$right_minor" ]; then
		return 0
	fi
	return 1
}
