#!/usr/bin/env bash
# Collect user input and set version-specific variables

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
		PYTHON_VER="3.11"
		FRAPPE_BRANCH="version-15"
		NODE_VER="24"
	else
		PYTHON_VER="3.14"
		FRAPPE_BRANCH="version-16"
		NODE_VER="24"
	fi

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
	[ -n "$DOMAIN" ] && echo "  Domain: $DOMAIN" || echo "  Mode: Development"
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
