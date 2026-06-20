#!/usr/bin/env bash

configure_mariadb() {
	log_info "Configuring MariaDB..."

	if ! sudo systemctl is-active --quiet mariadb; then
		log_info "Starting MariaDB..."
		sudo systemctl start mariadb
		sleep 3
	fi

	if [ -n "${MYSQL_ROOT_PASS:-}" ]; then
		log_info "Using MariaDB password from config"
	else
		echo ""
		echo "============================================"
		echo "  MariaDB Password Setup"
		echo "============================================"
		echo ""
		
		while true; do
			read -sp "Enter MariaDB root password (new or existing): " MYSQL_ROOT_PASS
			echo
			
			if [ -z "$MYSQL_ROOT_PASS" ]; then
				log_warn "Password cannot be empty"
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

		log_info "Setting MariaDB root password..."
		sudo mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS'; FLUSH PRIVILEGES;" 2>/dev/null || true
	fi

	if ! mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
		log_error "MariaDB password verification failed"
		log_info "Try: sudo mysql -uroot and set password manually"
		exit 1
	fi

	log_success "MariaDB password verified"
	_apply_mariadb_config
}

_apply_mariadb_config() {
	log_info "Applying MariaDB configuration..."

	local mem_mb
	mem_mb=$(free -m | awk '/^Mem:/{print $2}')
	local buffer_pool_size="256M"
	[ "$mem_mb" -ge 8192 ] && buffer_pool_size="1G"
	[ "$mem_mb" -ge 16384 ] && buffer_pool_size="2G"

	sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_buffer_pool_size = $buffer_pool_size
innodb_log_file_size = 64M
innodb_file_per_table = 1

[mysql]
default-character-set = utf8mb4
EOF

	if sudo systemctl restart mariadb; then
		log_success "MariaDB configured"
		sleep 2
	else
		log_warn "MariaDB restart failed"
		sudo rm -f /etc/mysql/mariadb.conf.d/99-frappe.cnf
		sudo systemctl restart mariadb
	fi
}
