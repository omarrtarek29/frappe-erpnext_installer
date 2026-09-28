#!/usr/bin/env bash

system_checks() {
	log_info "Checking system compatibility..."

	if [ "$EUID" -eq 0 ]; then
		log_warn "Running as root. Will create/use the Frappe user for bench operations."
		RUNNING_AS_ROOT=true
	else
		RUNNING_AS_ROOT=false
		if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
			if ! sudo -n true 2>/dev/null; then
				log_error "Non-interactive mode needs passwordless sudo, or run the installer as root."
				exit 1
			fi
		else
			log_info "Administrator access is required. Enter your sudo password if prompted."
			if ! sudo -v; then
				log_error "sudo authentication failed"
				exit 1
			fi
		fi
	fi
	export RUNNING_AS_ROOT

	TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
	if [ "$TOTAL_MEM" -lt 4096 ]; then
		log_warn "System has ${TOTAL_MEM}MB RAM. ERPNext needs at least 4 GB; 8 GB is safer for production."
	fi

	. /etc/os-release 2>/dev/null || true
	case "${VERSION_ID:-}" in
		26.04)
			log_success "Ubuntu 26.04 detected"
			log_info "Install plan: MariaDB 11.8 from Ubuntu, Python via uv, Node.js 24 via nvm."
			;;
		22.04|24.04)
			log_success "Ubuntu ${VERSION_ID} detected"
			log_info "Install plan: MariaDB from Ubuntu when it is new enough, otherwise the MariaDB repo. Python via uv. Node.js 24 via nvm."
			;;
		20.04)
			log_success "Ubuntu 20.04 detected"
			log_info "Install plan: MariaDB 10.6+ or 11.8 from the MariaDB repository. Ubuntu 20.04's own package is too old. Python via uv. Node.js 24 via nvm."
			;;
		*)
			log_warn "Untested Ubuntu version: ${VERSION_ID:-unknown}. Supported releases are 20.04, 22.04, 24.04, and 26.04."
			;;
	esac

	assert_install_disk_space
}

assert_install_disk_space() {
	local avail_kb min_avail_kb avail_h size_h
	# Bench, ERPNext, and Yarn need room to unpack. 8 GB free is the minimum that survives asset install.
	min_avail_kb=$((8 * 1024 * 1024))
	avail_kb="$(df -Pk / | awk 'NR==2 { print $4 }')"
	avail_h="$(df -h / | awk 'NR==2 { print $4 }')"
	size_h="$(df -h / | awk 'NR==2 { print $2 }')"

	if [ "${avail_kb:-0}" -ge "$min_avail_kb" ]; then
		log_success "Disk space: ${avail_h} free on ${size_h}"
		return 0
	fi

	log_error "Root filesystem is ${size_h} with ${avail_h} free."
	log_error "Frappe and ERPNext need at least 8 GB free. A 20 GB disk is a practical minimum."
	log_error "Expand the root volume, then run the installer again."
	exit 1
}

assert_os_for_frappe_version() {
	return 0
}
