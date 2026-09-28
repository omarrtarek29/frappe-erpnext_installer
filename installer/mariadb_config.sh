#!/usr/bin/env bash

configure_mariadb() {
	log_info "Configuring MariaDB..."

	if ! sudo systemctl is-active --quiet mariadb; then
		log_info "Starting MariaDB..."
		if ! sudo systemctl start mariadb; then
			_move_aside_frappe_mariadb_config
			sudo systemctl start mariadb
		fi
		sleep 3
	fi

	if [ -z "${MYSQL_ROOT_PASS:-}" ]; then
		if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
			log_error "MYSQL_ROOT_PASS is required in non-interactive mode"
			exit 1
		fi
		_prompt_mysql_root_password
	fi

	if ! _mysql_root_password_works; then
		log_info "Setting MariaDB root password..."
		_set_mysql_root_password || {
			log_error "Could not set the MariaDB root password"
			log_info "Try: sudo mysql -uroot and set the password manually"
			exit 1
		}
	fi

	if ! _mysql_root_password_works; then
		log_error "MariaDB password verification failed"
		exit 1
	fi

	log_success "MariaDB password verified"
	_apply_mariadb_config

	if ! _mysql_root_password_works; then
		log_error "MariaDB rejected the root password after restart"
		exit 1
	fi
}

_prompt_mysql_root_password() {
	echo ""
	echo "============================================"
	echo "  MariaDB Password Setup"
	echo "============================================"
	echo ""

	while true; do
		read -sp "Enter MariaDB root password (new or existing): " MYSQL_ROOT_PASS
		echo

		if ! validate_password_value "${MYSQL_ROOT_PASS:-}"; then
			log_warn "Password cannot be empty or contain a newline"
			continue
		fi

		read -sp "Confirm password: " MYSQL_ROOT_PASS_CONFIRM
		echo

		if [ "$MYSQL_ROOT_PASS" != "$MYSQL_ROOT_PASS_CONFIRM" ]; then
			log_warn "Passwords do not match"
			continue
		fi

		break
	done
}

_mysql_defaults_file() {
	local path="$1"
	local escaped old_umask
	escaped="$(printf '%s' "$MYSQL_ROOT_PASS" | sed 's/\\/\\\\/g; s/"/\\"/g')"
	old_umask="$(umask)"
	umask 077
	cat > "$path" <<EOF
[client]
user=root
password="${escaped}"
EOF
	chmod 600 "$path"
	umask "$old_umask"
}

_mysql_root_password_works() {
	local defaults status=0
	defaults="$(mktemp)"
	_mysql_defaults_file "$defaults"
	sudo chown "$FRAPPE_USER:$FRAPPE_USER" "$defaults"
	sudo chmod 600 "$defaults"
	sudo -n -u "$FRAPPE_USER" mysql --defaults-extra-file="$defaults" -e "SELECT 1;" &>/dev/null || status=$?
	sudo rm -f "$defaults"
	return "$status"
}

_set_mysql_root_password() {
	local escaped
	escaped="$(sql_escape_string "$MYSQL_ROOT_PASS")"
	sudo mysql --protocol=socket -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('${escaped}'); FLUSH PRIVILEGES;" || true
	if _mysql_root_password_works; then
		return 0
	fi
	sudo mysql --protocol=socket -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped}'; FLUSH PRIVILEGES;"
}

_apply_mariadb_config() {
	log_info "Applying MariaDB configuration..."

	local mem_mb
	mem_mb="$(free -m | awk '/^Mem:/{print $2}')"
	local buffer_pool_size="256M"
	[ "$mem_mb" -ge 8192 ] && buffer_pool_size="1G"
	[ "$mem_mb" -ge 16384 ] && buffer_pool_size="2G"

	sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_buffer_pool_size = $buffer_pool_size
innodb_file_per_table = 1

[mysql]
default-character-set = utf8mb4
EOF

	if sudo systemctl restart mariadb; then
		log_success "MariaDB configured"
		sleep 2
		return 0
	fi

	log_error "MariaDB failed to restart with the Frappe charset settings"
	sudo journalctl -u mariadb -n 40 --no-pager 2>/dev/null || true
	_move_aside_frappe_mariadb_config
	sudo systemctl start mariadb || true
	exit 1
}

_move_aside_frappe_mariadb_config() {
	local cnf="/etc/mysql/mariadb.conf.d/99-frappe.cnf"
	if [ -f "$cnf" ]; then
		log_warn "Moving $cnf aside so MariaDB can start"
		sudo mv "$cnf" "${cnf}.broken"
	fi
}
