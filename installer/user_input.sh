#!/usr/bin/env bash

collect_user_input() {
	echo ""
	echo "=========================================="
	echo "   Frappe/ERPNext Installation Wizard"
	echo "=========================================="
	echo ""

	read -p "Enter Frappe version (15 or 16): " FRAPPE_VER
	if [ "$FRAPPE_VER" != "15" ] && [ "$FRAPPE_VER" != "16" ]; then
		log_error "Invalid version. Enter 15 or 16"
		exit 1
	fi

	read -p "Enter system user for Frappe: " FRAPPE_USER
	if [ -z "$FRAPPE_USER" ]; then
		log_error "Username cannot be empty"
		exit 1
	fi

	read -p "Enter bench name [frappe-bench]: " BENCH_NAME
	BENCH_NAME=${BENCH_NAME:-frappe-bench}

	read -p "Enter site name: " SITE_NAME
	if [ -z "$SITE_NAME" ]; then
		log_error "Site name cannot be empty"
		exit 1
	fi

	read -sp "Enter admin password: " ADMIN_PASS
	echo
	if [ -z "$ADMIN_PASS" ]; then
		log_error "Admin password cannot be empty"
		exit 1
	fi

	read -p "Enter domain (leave empty for dev mode): " DOMAIN

	if [ "$FRAPPE_VER" = "15" ]; then
		PYTHON_VER="${PYTHON_VER:-3.11}"
		FRAPPE_BRANCH="version-15"
	else
		PYTHON_VER="${PYTHON_VER:-3.14}"
		FRAPPE_BRANCH="version-16"
	fi
	NODE_VER="${NODE_VER:-24}"

	FRAPPE_HOME="/home/$FRAPPE_USER"
	BENCH_PATH="$FRAPPE_HOME/$BENCH_NAME"

	echo ""
	log_info "Configuration Summary:"
	echo "  Frappe Version: $FRAPPE_VER"
	echo "  Python: $PYTHON_VER"
	echo "  Node.js: $NODE_VER"
	echo "  User: $FRAPPE_USER"
	echo "  Bench Path: $BENCH_PATH"
	echo "  Site: $SITE_NAME"
	[ -n "$DOMAIN" ] && echo "  Domain: $DOMAIN" || echo "  Environment: Development"
}

ask_install_erpnext() {
	echo ""
	read -p "Install ERPNext app on this site now? [Y/n]: " INSTALL_CHOICE
	INSTALL_CHOICE=${INSTALL_CHOICE:-Y}

	case "$INSTALL_CHOICE" in
	[Yy]*)
		INSTALL_ERPNEXT="yes"
		;;
	[Nn]*)
		INSTALL_ERPNEXT="no"
		;;
	*)
		INSTALL_ERPNEXT="yes"
		;;
	esac
}

apply_input_validation() {
	local errors=0

	if ! validate_linux_user "${FRAPPE_USER:-}"; then
		log_error "FRAPPE_USER must be a lowercase Linux username (letters, digits, underscore, hyphen)"
		errors=$((errors + 1))
	fi
	if ! validate_bench_name "${BENCH_NAME:-}"; then
		log_error "BENCH_NAME may only contain letters, digits, dots, underscores, and hyphens"
		errors=$((errors + 1))
	fi
	if ! validate_site_name "${SITE_NAME:-}"; then
		log_error "SITE_NAME must be a hostname such as site.local or erp.example.com"
		errors=$((errors + 1))
	fi
	if ! validate_optional_domain "${DOMAIN:-}"; then
		log_error "DOMAIN must be a hostname, or empty for development mode"
		errors=$((errors + 1))
	fi
	if ! validate_password_value "${ADMIN_PASS:-}"; then
		log_error "ADMIN_PASS cannot be empty or contain a newline"
		errors=$((errors + 1))
	fi
	if ! validate_choice "${INSTALL_ERPNEXT:-yes}"; then
		log_error "INSTALL_ERPNEXT must be yes or no"
		errors=$((errors + 1))
	fi
	if ! validate_choice "${FORCE_SITE:-no}"; then
		log_error "FORCE_SITE must be yes or no"
		errors=$((errors + 1))
	fi
	if ! validate_optional_email "${SSL_EMAIL:-}"; then
		log_error "SSL_EMAIL must be an email address"
		errors=$((errors + 1))
	fi
	if [ -n "${MYSQL_ROOT_PASS:-}" ] && ! validate_password_value "$MYSQL_ROOT_PASS"; then
		log_error "MYSQL_ROOT_PASS cannot contain a newline"
		errors=$((errors + 1))
	fi
	if [ "${NON_INTERACTIVE:-false}" = "true" ] && [ -z "${MYSQL_ROOT_PASS:-}" ]; then
		log_error "MYSQL_ROOT_PASS is required when using --yes"
		errors=$((errors + 1))
	fi

	[ "$errors" -eq 0 ]
}
