#!/usr/bin/env bash

set -e
export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$SCRIPT_DIR/installer"
LOCK_FILE="/tmp/frappe_installer.lock"

cleanup() {
	stop_sudo_keepalive
	rm -f "$LOCK_FILE" 2>/dev/null || true
}

acquire_lock() {
	if [ -f "$LOCK_FILE" ]; then
		local pid
		pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo "Another installer instance is running (PID: $pid)"
			exit 1
		fi
		rm -f "$LOCK_FILE"
	fi
	echo $$ > "$LOCK_FILE"
}

source "$INSTALLER_DIR/common.sh"
source "$INSTALLER_DIR/system_checks.sh"
source "$INSTALLER_DIR/user_input.sh"
source "$INSTALLER_DIR/system_packages.sh"
source "$INSTALLER_DIR/mariadb_config.sh"
source "$INSTALLER_DIR/bench_setup.sh"
source "$INSTALLER_DIR/mode_production.sh"
source "$INSTALLER_DIR/mode_dev.sh"
source "$INSTALLER_DIR/firewall.sh"
source "$INSTALLER_DIR/summary.sh"

show_usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Frappe/ERPNext Installer for Ubuntu 20.04, 22.04, 24.04

Options:
  -h, --help          Show this help message
  -c, --config FILE   Load configuration from file
  -y, --yes           Non-interactive mode (requires --config)

Environment Variables (can be set in config file):
  FRAPPE_VER          Frappe version (15 or 16)
  FRAPPE_USER         System user for Frappe
  BENCH_NAME          Bench directory name
  SITE_NAME           Site name
  ADMIN_PASS          Administrator password
  DOMAIN              Domain for production (empty for dev mode)
  MYSQL_ROOT_PASS     MariaDB root password
  INSTALL_ERPNEXT     Install ERPNext (yes/no)
  SSL_EMAIL           Email for SSL certificate notifications

EOF
}

load_config() {
	local config_file="$1"
	if [ -f "$config_file" ]; then
		log_info "Loading config from $config_file"
		set -a
		source "$config_file"
		set +a
	else
		log_error "Config file not found: $config_file"
		exit 1
	fi
}

main() {
	local config_file=""
	local non_interactive=false

	while [[ $# -gt 0 ]]; do
		case $1 in
			-h|--help) show_usage; exit 0 ;;
			-c|--config) config_file="$2"; shift 2 ;;
			-y|--yes) non_interactive=true; shift ;;
			*) log_error "Unknown option: $1"; show_usage; exit 1 ;;
		esac
	done

	acquire_lock
	trap cleanup EXIT

	system_checks

	if [ -n "$config_file" ]; then
		load_config "$config_file"
		validate_config
	else
		collect_user_input
	fi

	if [ "${RUNNING_AS_ROOT:-false}" = "true" ]; then
		keep_sudo_alive_root
	else
		keep_sudo_alive
	fi

	install_system_packages
	configure_mariadb
	install_bench_and_site
	ensure_bench_global
	
	if [ "$non_interactive" = "false" ] && [ -z "${INSTALL_ERPNEXT:-}" ]; then
		ask_install_erpnext
	fi

	install_apps_with_temp_redis

	if [ -n "$DOMAIN" ]; then
		setup_production
	else
		setup_dev_mode
	fi

	configure_firewall
	print_summary
}

validate_config() {
	local errors=0

	[ -z "${FRAPPE_VER:-}" ] && { log_error "FRAPPE_VER required"; errors=$((errors+1)); }
	[ -z "${FRAPPE_USER:-}" ] && { log_error "FRAPPE_USER required"; errors=$((errors+1)); }
	[ -z "${SITE_NAME:-}" ] && { log_error "SITE_NAME required"; errors=$((errors+1)); }
	[ -z "${ADMIN_PASS:-}" ] && { log_error "ADMIN_PASS required"; errors=$((errors+1)); }

	if [ "$FRAPPE_VER" != "15" ] && [ "$FRAPPE_VER" != "16" ]; then
		log_error "FRAPPE_VER must be 15 or 16"
		errors=$((errors+1))
	fi

	[ $errors -gt 0 ] && exit 1

	BENCH_NAME="${BENCH_NAME:-frappe-bench}"
	INSTALL_ERPNEXT="${INSTALL_ERPNEXT:-yes}"

	if [ "$FRAPPE_VER" = "15" ]; then
		PYTHON_VER="3.11"
		FRAPPE_BRANCH="version-15"
		NODE_VER="20"
	else
		PYTHON_VER="3.12"
		FRAPPE_BRANCH="version-16"
		NODE_VER="20"
	fi

	FRAPPE_HOME="/home/$FRAPPE_USER"
	BENCH_PATH="$FRAPPE_HOME/$BENCH_NAME"

	log_info "Configuration validated"
}

keep_sudo_alive_root() {
	log_info "Running as root - no sudo keepalive needed"
	SUDO_KEEPALIVE_PID=""
}

main "$@"
