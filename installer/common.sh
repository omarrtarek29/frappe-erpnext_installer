#!/usr/bin/env bash
# Common logging and helper functions for Frappe/ERPNext installer

log_info() {
	echo -e "\n\033[1;34m[INFO]\033[0m $1"
}

log_success() {
	echo -e "\033[1;32m[✓]\033[0m $1"
}

log_warn() {
	echo -e "\033[1;33m[WARN]\033[0m $1"
}

log_error() {
	echo -e "\033[1;31m[ERROR]\033[0m $1"
}

command_exists() {
	command -v "$1" &>/dev/null
}

safe_apt_install() {
	log_info "Installing: $*"
	sudo apt-get install -y "$@" || {
		log_warn "Fixing broken packages..."
		sudo apt-get -f install -y
		sudo dpkg --configure -a
		sudo apt-get install -y "$@"
	}
}
