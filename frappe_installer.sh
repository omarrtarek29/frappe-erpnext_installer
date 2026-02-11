#!/usr/bin/env bash
###########################################
# Frappe/ERPNext Universal Installer
# Supports: Ubuntu 20.04, 22.04, 24.04+
###########################################

set -e
export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$SCRIPT_DIR/installer"

# Load modules
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

main() {
	system_checks
	collect_user_input
	install_system_packages
	configure_mariadb
	install_bench_and_site
	ask_install_erpnext

	if [ -n "$DOMAIN" ]; then
		setup_production
	else
		setup_dev_mode
	fi

	configure_firewall
	print_summary
}

main "$@"
