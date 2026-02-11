#!/usr/bin/env bash
# MariaDB root password and Frappe-specific configuration

configure_mariadb() {
	log_info "Configuring MariaDB..."

	MYSQL_ROOT_PASS=""
	read -p "Do you have a MariaDB root password? (y/n): " HAS_PASSWORD

	if [ "$HAS_PASSWORD" = "y" ] || [ "$HAS_PASSWORD" = "Y" ]; then
		while true; do
			read -sp "Enter MariaDB root password: " MYSQL_ROOT_PASS
			echo
			if sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
				log_success "Password verified"
				break
			else
				log_warn "Incorrect password"
				read -p "Try again? (y/n): " RETRY
				[ "$RETRY" != "y" ] && [ "$RETRY" != "Y" ] && exit 1
			fi
		done
	else
		if sudo mysql -uroot -e "SELECT 1;" &>/dev/null; then
			read -p "Set a new MariaDB root password? (y/n): " SET_PASS
			if [ "$SET_PASS" = "y" ] || [ "$SET_PASS" = "Y" ]; then
				read -sp "Enter new password: " MYSQL_ROOT_PASS
				echo
				read -sp "Confirm password: " MYSQL_ROOT_PASS_CONFIRM
				echo
				if [ "$MYSQL_ROOT_PASS" != "$MYSQL_ROOT_PASS_CONFIRM" ]; then
					log_error "Passwords do not match"
					exit 1
				fi
				sudo mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
FLUSH PRIVILEGES;
SQL
				log_success "Password set successfully"
			else
				log_info "Using socket authentication"
			fi
		else
			log_error "Cannot access MariaDB. Please configure it manually"
			exit 1
		fi
	fi

	log_info "Applying MariaDB configuration..."
	sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_buffer_pool_size = 256M

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
