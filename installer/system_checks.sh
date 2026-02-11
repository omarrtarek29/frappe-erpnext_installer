#!/usr/bin/env bash
# System compatibility checks (root, RAM)

system_checks() {
	log_info "Checking system compatibility..."

	if [ "$EUID" -eq 0 ]; then
		log_error "Please run as a regular user with sudo privileges, not as root"
		exit 1
	fi

	TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
	if [ "$TOTAL_MEM" -lt 2048 ]; then
		log_warn "System has ${TOTAL_MEM}MB RAM. Minimum 4GB recommended"
	fi
}
