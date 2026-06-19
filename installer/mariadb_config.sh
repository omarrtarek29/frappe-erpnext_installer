#!/usr/bin/env bash

configure_mariadb() {
	log_info "Configuring MariaDB..."

	local auth_method
	auth_method=$(_detect_mariadb_auth)

	case "$auth_method" in
		"password_provided")
			log_info "Using provided MariaDB password from config"
			if ! mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
				log_error "Provided MariaDB password is incorrect"
				exit 1
			fi
			log_success "MariaDB password verified"
			;;
		"password_works")
			log_info "MariaDB root already uses password authentication"
			_configure_mariadb_interactive
			;;
		"socket_only")
			log_info "MariaDB using unix_socket authentication"
			_setup_mariadb_password_auth
			;;
		*)
			log_error "Cannot determine MariaDB auth method"
			exit 1
			;;
	esac

	_verify_mariadb_access
	_apply_mariadb_config
}

_detect_mariadb_auth() {
	if [ -n "${MYSQL_ROOT_PASS:-}" ]; then
		echo "password_provided"
		return
	fi

	if mysql -uroot -e "SELECT 1;" &>/dev/null 2>&1; then
		echo "password_works"
		return
	fi

	if sudo mysql -uroot -e "SELECT 1;" &>/dev/null 2>&1; then
		echo "socket_only"
		return
	fi

	echo "unknown"
}

_setup_mariadb_password_auth() {
	echo ""
	echo "============================================"
	echo "  MariaDB Password Setup"
	echo "============================================"
	echo ""
	echo "MariaDB is using socket authentication (no password)."
	echo "Frappe/ERPNext requires password authentication to work."
	echo ""
	echo "You need to set a password for the MariaDB root user."
	echo ""

	while true; do
		read -sp "Enter NEW MariaDB root password: " MYSQL_ROOT_PASS
		echo
		
		if [ -z "$MYSQL_ROOT_PASS" ]; then
			log_warn "Password cannot be empty. Please try again."
			continue
		fi

		read -sp "Confirm password: " MYSQL_ROOT_PASS_CONFIRM
		echo

		if [ "$MYSQL_ROOT_PASS" != "$MYSQL_ROOT_PASS_CONFIRM" ]; then
			log_warn "Passwords do not match. Please try again."
			continue
		fi

		break
	done

	log_info "Configuring MariaDB password authentication..."

	sudo mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MYSQL_ROOT_PASS');
FLUSH PRIVILEGES;
SQL

	if mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
		log_success "MariaDB password set successfully"
		return 0
	fi

	log_warn "First method failed, trying alternative..."
	sudo mysql -uroot <<SQL2
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASS';
FLUSH PRIVILEGES;
SQL2

	if mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
		log_success "MariaDB password set successfully"
		return 0
	fi

	log_error "Could not configure MariaDB password authentication"
	log_info "Try manually: sudo mysql -uroot -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'yourpass';\""
	exit 1
}

_configure_mariadb_interactive() {
	echo ""
	read -p "Do you already have a MariaDB root password set? (y/n): " HAS_PASSWORD

	if [ "$HAS_PASSWORD" = "y" ] || [ "$HAS_PASSWORD" = "Y" ]; then
		local attempts=0
		while [ $attempts -lt 3 ]; do
			read -sp "Enter your existing MariaDB root password: " MYSQL_ROOT_PASS
			echo
			if mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
				log_success "Password verified"
				return 0
			else
				attempts=$((attempts + 1))
				log_warn "Incorrect password (attempt $attempts/3)"
				if [ $attempts -ge 3 ]; then
					log_error "Too many failed attempts"
					exit 1
				fi
				read -p "Try again? (y/n): " RETRY
				[ "$RETRY" != "y" ] && [ "$RETRY" != "Y" ] && exit 1
			fi
		done
	else
		log_info "Checking MariaDB access..."
		if sudo mysql -uroot -e "SELECT 1;" &>/dev/null; then
			log_info "MariaDB accessible via socket - will set up password"
			_setup_mariadb_password_auth
		else
			log_error "Cannot access MariaDB. Please check MariaDB is running:"
			log_info "  sudo systemctl status mariadb"
			exit 1
		fi
	fi
}

_verify_mariadb_access() {
	log_info "Verifying MariaDB access for bench..."

	if [ -n "$MYSQL_ROOT_PASS" ]; then
		if mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
			log_success "MariaDB password auth working"
			return 0
		fi
	fi

	log_error "MariaDB access verification failed"
	log_info "bench new-site requires password authentication"
	exit 1
}

_apply_mariadb_config() {
	log_info "Applying MariaDB configuration for Frappe..."

	local mem_mb
	mem_mb=$(free -m | awk '/^Mem:/{print $2}')
	local buffer_pool_size="256M"
	[ "$mem_mb" -ge 8192 ] && buffer_pool_size="1G"
	[ "$mem_mb" -ge 16384 ] && buffer_pool_size="2G"

	sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf >/dev/null <<EOF
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb_buffer_pool_size = $buffer_pool_size
innodb_log_file_size = 64M
innodb_file_per_table = 1

[mysql]
default-character-set = utf8mb4
EOF

	if sudo systemctl restart mariadb; then
		log_success "MariaDB configured (buffer_pool: $buffer_pool_size)"
		sleep 2
	else
		log_warn "MariaDB restart failed - removing custom config"
		sudo rm -f /etc/mysql/mariadb.conf.d/99-frappe.cnf
		sudo systemctl restart mariadb
	fi
}
