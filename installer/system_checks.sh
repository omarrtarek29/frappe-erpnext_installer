#!/usr/bin/env bash

system_checks() {
	log_info "Checking system compatibility..."

	if [ "$EUID" -eq 0 ]; then
		log_warn "Running as root. Will create/use frappe user for bench operations."
		RUNNING_AS_ROOT=true
	else
		RUNNING_AS_ROOT=false
		if ! sudo -n true 2>/dev/null; then
			log_error "User must have passwordless sudo or run as root"
			exit 1
		fi
	fi
	export RUNNING_AS_ROOT

	TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
	if [ "$TOTAL_MEM" -lt 4096 ]; then
		log_warn "System has ${TOTAL_MEM}MB RAM. Minimum 4GB recommended for production"
	fi

	. /etc/os-release 2>/dev/null || true
	case "${VERSION_ID:-}" in
		20.04|22.04|24.04) log_success "Ubuntu ${VERSION_ID} detected" ;;
		*) log_warn "Untested Ubuntu version: ${VERSION_ID:-unknown}" ;;
	esac
}
